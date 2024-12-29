module emu.hw.hollywood.hollywood;

import bindbc.opengl;
import emu.hw.hollywood.blitting_processor;
import emu.hw.hollywood.texture;
import emu.hw.memory.strategy.memstrategy;
import std.file;
import util.bitop;
import util.force_cast;
import util.log;
import util.number;

final class Hollywood {
    enum GXFifoCommand {
        BlittingProcessor = 0x61,
        CommandProcessor  = 0x08,
        TransformUnit     = 0x10,

        VSInvalidate      = 0x48,
        End               = 0x00,

        DrawQuads         = 0x80,
    }

    enum State {
        WaitingForCommand,
        WaitingForBPWrite,
        WaitingForCPReg,
        WaitingForCPData,
        WaitingForTransformUnitDescriptor,
        WaitingForTransformUnitData,
        WaitingForNumberOfVertices,
        WaitingForVertexData,
        Ignore,
    }

    enum VertexAttributeLocation {
        NotPresent = 0,
        Direct = 1,
        Indexed8Bit = 2,
        Indexed16Bit = 3,
    }

    struct VertexDescriptor {
        VertexAttributeLocation    position_normal_matrix_location;
        VertexAttributeLocation[8] texcoord_matrix_location;
        VertexAttributeLocation    position_location;
        VertexAttributeLocation    normal_location;
        VertexAttributeLocation[2] color_location;
        VertexAttributeLocation[8] texcoord_location;
    }

    struct Vertex {
        // figure out the other fields later, as they get used
        // these are probably just the same as the stuff in the
        // vertex descriptor
        
        float[3] position;
        float[3] normal;
        float[2] texcoord;
    }

    struct Shape {
        Vertex[] vertices;
        Color* texture;
    }

    Shape[] shapes;
    VertexDescriptor[8] vertex_descriptors;
    TextureDescriptor[8] texture_descriptors;

    private State state;
    private BlittingProcessor blitting_processor;
    private u8 cp_register;

    private u16 xf_register;
    private u16 xf_data_remaining;

    private GXFifoCommand current_draw_command;
    private int current_vat;
    private int number_of_expected_vertices;
    private int number_of_expected_writes_for_shape;
    private int number_of_received_writes_for_shape;
    
    // if this isn't enough, i will eat a toad
    private u32[0x1000] shape_data;
    private int bazinga;

    private GLfloat[16] projection_matrix = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    private GLuint gl_program;
    
    this() {
        blitting_processor = new BlittingProcessor();
        state = State.WaitingForCommand;

        auto vertex_shader   = glCreateShader(GL_VERTEX_SHADER);
        auto fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);	

        string vertex_text   = readText("source/emu/hw/hollywood/shaders/vertex.glsl");
        string fragment_text = readText("source/emu/hw/hollywood/shaders/fragment.glsl");
        GLint vertex_text_length = cast(GLint) vertex_text.length;
        GLint fragment_text_length = cast(GLint) fragment_text.length;

        auto vertex_text_const_char  = cast(const char*) vertex_text.ptr;
        auto fragment_text_const_char = cast(const char*) fragment_text.ptr;
        glShaderSource(vertex_shader,   1, &vertex_text_const_char,   &vertex_text_length);
        glShaderSource(fragment_shader, 1, &fragment_text_const_char, &fragment_text_length);
        
        GLint compiled;

        glCompileShader(vertex_shader);
        glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled) {
            error_hollywood("Vertex shader compilation error.");
        } 

        glCompileShader(fragment_shader);
        glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled) {
            error_hollywood("Fragment shader compilation error.");
        } 
        
        gl_program = glCreateProgram();

        glBindAttribLocation(gl_program, 0, "in_Position");
            
        glAttachShader(gl_program, vertex_shader);
        glAttachShader(gl_program, fragment_shader);
        
        glLinkProgram(gl_program);
        glUseProgram(gl_program);
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    void write_GX_FIFO(T)(T value, int offset) {
        // assert(offset == 0);
        log_hollywood("write_GX_FIFO: %08x, %x", value, T.sizeof);

        final switch (state) {
            case State.WaitingForCommand:
                handle_new_command(value, offset);
                break;

            case State.WaitingForBPWrite:
                static if (is(T == u32)) {
                    handle_new_bp_write(value);
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

                state = State.WaitingForCommand;
                break;
            
            case State.WaitingForCPReg:
                static if (is(T == u8)) {
                    cp_register = value;
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

            state = State.WaitingForCPData;
                break;
            
            case State.WaitingForCPData:
                static if (is(T == u32)) {
                    handle_new_cp_write(cp_register, value);
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

                state = State.WaitingForCommand;
                break;

            case State.WaitingForTransformUnitDescriptor:
                static if (is(T == u32)) {
                    xf_register       = cast(u16)  value.bits(0, 15);
                    xf_data_remaining = cast(u16) (value.bits(16, 31) + 1);
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

                state = State.WaitingForTransformUnitData;
                break;
            
            case State.WaitingForTransformUnitData:
                static if (is(T == u32)) {
                    handle_new_transform_unit_write(xf_register, value);

                    xf_data_remaining -= 1;
                    xf_register += 1;
                    log_hollywood("Transform unit data: %04x %08x (%d left)", xf_register, value, xf_data_remaining);

                    if (xf_data_remaining == 0) {
                        state = State.WaitingForCommand;
                    }
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }
                break;
            
            case State.Ignore:
                bazinga--;
                if (bazinga == 0) {
                    state = State.WaitingForCommand;
                }

                break;
            
            case State.WaitingForNumberOfVertices:
                static if (is(T == u16)) {
                    number_of_expected_vertices = value;
                    number_of_expected_writes_for_shape = size_of_incoming_vertex(current_vat) * number_of_expected_vertices;
                    
                    state = State.WaitingForVertexData;
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

                break;
            
            case State.WaitingForVertexData:
                static if (is(T == u32)) {
                    shape_data[number_of_received_writes_for_shape] = value;
                    number_of_received_writes_for_shape++;

                    if (number_of_received_writes_for_shape == number_of_expected_writes_for_shape) {
                        process_new_shape();
                        state = State.WaitingForCommand;
                        number_of_received_writes_for_shape = 0;
                    }
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

                break;
        }
    }

    private void handle_new_command(T)(T value, int offset) {
        // assert(value.sizeof == 1);
        auto command = cast(GXFifoCommand) value.bits(0, 7);

        switch (cast(int) command) {
            case GXFifoCommand.BlittingProcessor: state = State.WaitingForBPWrite; break;
            case GXFifoCommand.CommandProcessor:  state = State.WaitingForCPReg; break;
            case GXFifoCommand.TransformUnit:     state = State.WaitingForTransformUnitDescriptor; break;
            case GXFifoCommand.VSInvalidate:      log_hollywood("Unimplemented: VS invalidate"); break;
            case GXFifoCommand.End:               draw_vertices(); break;
            
            case GXFifoCommand.DrawQuads | 0: .. case GXFifoCommand.DrawQuads | 7:         
                current_draw_command = GXFifoCommand.DrawQuads;
                current_vat = (cast(int) command).bits(0, 2);
                state = State.WaitingForNumberOfVertices;
                break;
        
            default:
                error_hollywood("Unknown GX command: %02x", command);
                break;
        }
    }

    private void handle_draw_quads() {

    }

    void handle_new_bp_write(u32 value) {
        auto bp_register = value.bits(24, 31);
        auto bp_data = value.bits(0, 23);

        switch (bp_register) {
            case 0x49:
                blitting_processor.write_efb_boxcoord_x(cast(u16) bp_data.bits(0, 9));
                blitting_processor.write_efb_boxcoord_y(cast(u16) bp_data.bits(10, 19));
                break;
            
            case 0x4a:
                blitting_processor.write_efb_boxcoord_size_x(cast(u16) (bp_data.bits(0, 9) + 1));
                blitting_processor.write_efb_boxcoord_size_y(cast(u16) (bp_data.bits(10, 19) + 1));
                break;
            
            case 0x4b:
                blitting_processor.write_xfb_addr(bp_data << 5);
                break;
            
            case 0x4d:
                blitting_processor.write_xfb_stride(bp_data.bits(0, 9));
                break;
            
            case 0x52:
                log_hollywood("Unimplemented: BP copy");
                break;
            
            case 0x4F:
                blitting_processor.write_copy_clear_color_alpha(cast(u8) bp_data.bits(8, 15));
                blitting_processor.write_copy_clear_color_red(cast(u8) bp_data.bits(0, 7));
                break;

            case 0x50:
                blitting_processor.write_copy_clear_color_green(cast(u8) bp_data.bits(8, 15));
                blitting_processor.write_copy_clear_color_blue(cast(u8) bp_data.bits(0, 7));
                break;
            
            case 1:
                blitting_processor.write_bp_filter(bp_data, 0);
                break;
            
            case 2:
                blitting_processor.write_bp_filter(bp_data, 1);
                break;
            
            case 3:
                blitting_processor.write_bp_filter(bp_data, 2);
                break;
            
            case 4:
                blitting_processor.write_bp_filter(bp_data, 3);
                break;
            
            case 0x53:
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(0, 5), 0);
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(6, 11), 1);
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(12, 17), 2);
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(18, 23), 3);
                break;
            
            case 0x54:
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(0, 5), 4);
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(6, 11), 5);
                blitting_processor.write_bp_vfilter_0f(cast(u8) bp_data.bits(12, 17), 6);
                break;
            
            case 0x20:
                blitting_processor.write_mem_scissor_top(cast(u16) bp_data.bits(0, 10));
                blitting_processor.write_mem_scissor_left(cast(u16) bp_data.bits(12, 22));
                break;
            
            case 0x21:
                blitting_processor.write_mem_scissor_bottom(cast(u16) bp_data.bits(0, 10));
                blitting_processor.write_mem_scissor_right(cast(u16) bp_data.bits(12, 22));
                break;
            
            case 0x59:
                blitting_processor.write_mem_scissor_offset_x(cast(u16) (bp_data.bits(0, 8) << 1));
                blitting_processor.write_mem_scissor_offset_y(cast(u16) (bp_data.bits(10, 18) << 1));
                break;
            
            case 0x94: .. case 0x97:
            log_hollywood("Texture descriptor: %02x %08x", bp_register, bp_data);
                texture_descriptors[bp_register - 0x94].base_address = bp_data << 5;
                break;
            
            case 0xb4: .. case 0xb7:
                texture_descriptors[bp_register - 0xb4 + 4].base_address = bp_data << 5;
                break;
            
            case 0x88: .. case 0x8b:
            log_hollywood("Texture descriptor: %02x %08x", bp_register, bp_data);
                texture_descriptors[bp_register - 0x88].width  = bp_data.bits(0, 9) + 1;
                texture_descriptors[bp_register - 0x88].height = bp_data.bits(10, 19) + 1;
                texture_descriptors[bp_register - 0x88].type   = cast(TextureType) bp_data.bits(20, 23);
                break;
            
            case 0xa8: .. case 0xab:
                texture_descriptors[bp_register - 0xa8 + 4].width  = bp_data.bits(0, 9) + 1;
                texture_descriptors[bp_register - 0xa8 + 4].height = bp_data.bits(10, 19) + 1;
                texture_descriptors[bp_register - 0xa8 + 4].type   = cast(TextureType) bp_data.bits(20, 23);
                break;

            default:
                log_hollywood("Unimplemented: BP register %02x", bp_register);
                break;
        }
    }

    void handle_new_cp_write(u8 register, u32 value) {
        switch (register) {
            case 0x50: .. case 0x57:
                auto vcd = &vertex_descriptors[register - 0x50];
                
                vcd.texcoord_location = cast(VertexAttributeLocation) value.bit(0);
                vcd.texcoord_matrix_location[0] = cast(VertexAttributeLocation) value.bit(1);
                vcd.texcoord_matrix_location[1] = cast(VertexAttributeLocation) value.bit(2);
                vcd.texcoord_matrix_location[2] = cast(VertexAttributeLocation) value.bit(3);
                vcd.texcoord_matrix_location[3] = cast(VertexAttributeLocation) value.bit(4);
                vcd.texcoord_matrix_location[4] = cast(VertexAttributeLocation) value.bit(5);
                vcd.texcoord_matrix_location[5] = cast(VertexAttributeLocation) value.bit(6);
                vcd.texcoord_matrix_location[6] = cast(VertexAttributeLocation) value.bit(7);
                vcd.texcoord_matrix_location[7] = cast(VertexAttributeLocation) value.bit(8);
                vcd.position_location = cast(VertexAttributeLocation) value.bits(9, 10);
                vcd.normal_location = cast(VertexAttributeLocation) value.bits(11, 12);
                vcd.color_location[0] = cast(VertexAttributeLocation) value.bits(13, 14);
                vcd.color_location[1] = cast(VertexAttributeLocation) value.bits(15, 16);

                break;
            
            case 0x60: .. case 0x6F:
                auto vcd = &vertex_descriptors[register - 0x60];

                vcd.texcoord_location[0] = cast(VertexAttributeLocation) value.bits(0, 1);
                vcd.texcoord_location[1] = cast(VertexAttributeLocation) value.bits(2, 3);
                vcd.texcoord_location[2] = cast(VertexAttributeLocation) value.bits(4, 5);
                vcd.texcoord_location[3] = cast(VertexAttributeLocation) value.bits(6, 7);
                vcd.texcoord_location[4] = cast(VertexAttributeLocation) value.bits(8, 9);
                vcd.texcoord_location[5] = cast(VertexAttributeLocation) value.bits(10, 11);
                vcd.texcoord_location[6] = cast(VertexAttributeLocation) value.bits(12, 13);
                vcd.texcoord_location[7] = cast(VertexAttributeLocation) value.bits(14, 15);
                break;
            
            default:
                log_hollywood("Unimplemented: CP register %02x", register);
                break;
        }
    }

    private int size_of_incoming_vertex(int vat) {
        auto vcd = &vertex_descriptors[vat];
        int size = 0;

        if (vcd.position_location != VertexAttributeLocation.NotPresent) {
            size += 3;
        }

        if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
            error_hollywood("Normal location not implemented");
        }

        if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
            error_hollywood("Matrix location not implemented");
        }

        for (int i = 0; i < 8; i++) {
            if (vcd.texcoord_matrix_location[i] != VertexAttributeLocation.NotPresent) {
                error_hollywood("Matrix location not implemented");
            }
        }

        for (int i = 0; i < 2; i++) {
            if (vcd.color_location[i] != VertexAttributeLocation.NotPresent) {
                error_hollywood("Color location not implemented");
            }
        }

        for (int i = 0; i < 8; i++) {
            if (vcd.texcoord_location[i] != VertexAttributeLocation.NotPresent) {
                size += 2;
            }
        }

        return size;
    }

    private void handle_new_transform_unit_write(u16 register, u32 value) {
        switch (register) {
            case 0x1020: projection_matrix[0]  = force_cast!float(value); break;
            case 0x1021: projection_matrix[8]  = force_cast!float(value); break;
            case 0x1022: projection_matrix[5]  = force_cast!float(value); break;
            case 0x1023: projection_matrix[9]  = force_cast!float(value); break;
            case 0x1024: projection_matrix[10] = force_cast!float(value); break;
            case 0x1025: projection_matrix[15] = force_cast!float(value); break;
            
            default:
                log_hollywood("Unimplemented: Transform unit register %04x", register);
                break;
        }
    }

    private void process_new_shape() {        
        Shape shape;
        shape.vertices = [];
        shape.texture = null;

        int offset = 0;
        for (int i = 0; i < number_of_expected_vertices; i++) {
            Vertex v;
            
            auto vcd = &vertex_descriptors[current_vat];

            if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
                error_hollywood("Matrix location not implemented");
            }

            for (int j = 0; j < 8; j++) {
                if (vcd.texcoord_matrix_location[j] != VertexAttributeLocation.NotPresent) {
                    error_hollywood("Matrix location not implemented");
                }
            }
            
            if (vcd.position_location != VertexAttributeLocation.NotPresent) {
                v.position[0] = force_cast!float(shape_data[offset++]);
                v.position[1] = force_cast!float(shape_data[offset++]);
                v.position[2] = force_cast!float(shape_data[offset++]);
            }

            if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
                error_hollywood("Normal location not implemented");
            }

            for (int j = 0; j < 2; j++) {
                if (vcd.color_location[j] != VertexAttributeLocation.NotPresent) {
                    error_hollywood("Color location not implemented");
                }
            }

            for (int j = 0; j < 8; j++) {
                if (vcd.texcoord_location[j] == VertexAttributeLocation.Direct) {
                    v.texcoord[0] = force_cast!float(shape_data[offset++]);
                    v.texcoord[1] = force_cast!float(shape_data[offset++]);

                    // do this once
                    if (i == 0) {
                        // TODO: support multiple textures
                        shape.texture = load_texture(texture_descriptors[j], mem).ptr;
                        log_hollywood("Texture: %s", shape.texture);
                    }
                }
            }

            shape.vertices ~= v;
        }

        log_hollywood("Shape: %s", shape);
        shapes ~= shape;
    }

    // bool shit = false;
    private void draw_vertices() {
        // if (!shit) { shit = true; return; }
        // shit = false;

        foreach (Shape shape; shapes) {
            log_hollywood("projection_matrix: %s %d", projection_matrix, glGetUniformLocation(gl_program, "wiiscreen"));
            glUniformMatrix4fv(glGetUniformLocation(gl_program, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
            // GLfloat[16] projection_matrix = [
            //     0, 0, 0, 0,
            //     0, 0, 0, 0,
            //     0, 0, 0, 0,
            //     0, 0, 0, 0
            // ];

            // auto p = gl_program;
            // glUseProgram(p);
            // GLuint MatrixID = glGetUniformLocation(p, "MVP");
            // GLfloat[16] MVP = [0.00240385, 0, 0, 0, 0, 0.00438596, 0, 0, -0, -0, 0, 0, 0, 0, 0, 1];
            // auto sex = [

            // glUniformMatrix4fv(MatrixID, 1, GL_TRUE, MVP.ptr);

            
            if (shape.texture != null) {
                GLuint texture_id;
                glGenTextures(1, &texture_id);

                // "Bind" the newly created texture : all future texture functions will modify this texture
                glBindTexture(GL_TEXTURE_2D, texture_id);

                // Give the image to OpenGL
                log_hollywood("projection color: %s", shape.texture[0]);
                glTexImage2D(GL_TEXTURE_2D, 0,GL_RGB, 456, 832, 0, GL_BGR, GL_UNSIGNED_BYTE, shape.texture);

                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
 
                glUniform1i(glGetUniformLocation(gl_program, "wiiscreen"), 0);
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, texture_id);
            }

            // TODO: figure out how to generalize this
            if (shape.vertices.length != 4) {
                error_hollywood("Only quads are supported");
            }

            float[] vertex_data = shape.vertices[0].position ~ shape.vertices[1].position ~ shape.vertices[2].position;
            uint vertex_array_object;
            uint vertex_buffer_object;
            glGenVertexArrays(1, &vertex_array_object);
            glBindVertexArray(vertex_array_object);
            glGenBuffers(1, &vertex_buffer_object);
            glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object);
            glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, vertex_data.ptr, GL_STATIC_DRAW);
            glVertexAttribPointer(cast(GLuint) 0, 3, GL_FLOAT, GL_FALSE, 0, null); 
            glEnableVertexAttribArray(0);
            glDrawArrays(GL_TRIANGLES, 0, 4);

            vertex_data = shape.vertices[0].position ~ shape.vertices[2].position ~ shape.vertices[3].position;
            uint vertex_array_object2;
            uint vertex_buffer_object2;
            glGenVertexArrays(1, &vertex_array_object2);
            glBindVertexArray(vertex_array_object2);
            glGenBuffers(1, &vertex_buffer_object2);
            glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object2);
            glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, vertex_data.ptr, GL_STATIC_DRAW);
            glVertexAttribPointer(cast(GLuint) 0, 3, GL_FLOAT, GL_FALSE, 0, null); 
            glEnableVertexAttribArray(0);
            glDrawArrays(GL_TRIANGLES, 0, 4);

            log_hollywood("Drawing shape");
        }

        shapes = [];
    }
}