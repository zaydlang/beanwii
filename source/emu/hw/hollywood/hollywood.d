module emu.hw.hollywood.hollywood;

import bindbc.opengl;
import emu.hw.hollywood.blitting_processor;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.texture;
import emu.hw.memory.strategy.memstrategy;
import std.file;
import util.bitop;
import util.force_cast;
import util.log;
import util.number;

alias Shape = Hollywood.Shape;
alias ShapeGroup = Hollywood.ShapeGroup;

final class Hollywood {
    enum GXFifoCommand {
        BlittingProcessor = 0x61,
        CommandProcessor  = 0x08,
        TransformUnit     = 0x10,

        VSInvalidate      = 0x48,
        NoOp              = 0x00,

        DrawQuads         = 0x80,
        DrawTriangleFan   = 0xA0,
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

    struct VertexAttributeTable {
        CoordFormat position_format;
        int position_count;
        int position_shift;
        
        NormalFormat normal_format;
        int normal_count;
        int normal_shift;

        ColorFormat[2] color_format;
        int[2] color_count;
        int[2] color_shift;

        CoordFormat[8] texcoord_format;
        int[8] texcoord_count;
        int[8] texcoord_shift;
    }

    VertexAttributeTable[8] vats;

    struct Vertex {
        // figure out the other fields later, as they get used
        // these are probably just the same as the stuff in the
        // vertex descriptor
        
        float[3] position;
        float[3] normal;
        float[2] texcoord;
        float[4][8] color;
    }

    struct Texture {
        Color* data;
        size_t width;
        size_t height;
        TextureWrap wrap_s;
        TextureWrap wrap_t;

        float[12] dualtex_matrix;
        float[12] tex_matrix;
        bool dualtex_normal_enable;
    }

    struct ShapeGroup {    
        float[12] position_matrix;
        float[16] projection_matrix;
        Texture[8] texture;
        TevConfig tev_config;
        bool textured;

        Shape[] shapes;
    }

    struct Shape {
        Vertex[3] vertices;
    }

    enum ProjectionMode {
        Perspective = 0,
        Orthographic = 1,
    }

    enum CoordFormat {
        U8  = 0,
        S8  = 1,
        U16 = 2,
        S16 = 3,
        F32 = 4,
    }

    enum NormalFormat {
        S8  = 1,
        S16 = 3,
        F32 = 4,
    }

    enum ColorFormat {
        RGB565   = 0,
        RGB888   = 1,
        RGB888x  = 2,
        RGBA4444 = 3,
        RGBA6666 = 4,
        RGBA8888 = 5,
    }

    struct TevConfig {
        align(1):
        int num_tev_stages;

        u32[16] in_color_a;
        u32[16] in_color_b;
        u32[16] in_color_c;
        u32[16] in_color_d;
        u32[16] in_alfa_a;
        u32[16] in_alfa_b;
        u32[16] in_alfa_c;
        u32[16] in_alfa_d;
        u32[16] color_dest;
        u32[16] alfa_dest;
        float[16] bias_color;
        float[16] scale_color;
        float[16] bias_alfa;
        float[16] scale_alfa;
        int[3] dipshit_padding;

        float[4] reg0;
        float[4] reg1;
        float[4] reg2;
        float[4] reg3;

        float[4][16] ras;
        float[4] konst_a;
        float[4] konst_b;
        float[4] konst_c;
        float[4] konst_d;
    }

    enum RasChannelId {
        Color0    = 0,
        Color1    = 1,
        Alpha0    = 2,
        Alpha1    = 3,
        Color0A0  = 4,
        Color0A1  = 5,
        ColorZero = 6,
        AlphaBump = 7,
    }

    RasChannelId[16] ras_color;
    TevConfig tev_config;

    ProjectionMode projection_mode;

    ShapeGroup[] shape_groups;
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
    private GLfloat[6]  projection_matrix_parameters;
    private float[256] general_matrix_ram;
    private float[256] dt_texture_matrix_ram;

    private float[4] color_0_global;
    private float[4] color_1_global;

    private GLuint gl_program;

    private GlObjectManager gl_object_manager;
    
    void init_opengl() {
        blitting_processor = new BlittingProcessor();
        gl_object_manager = new GlObjectManager();

        state = State.WaitingForCommand;

        load_shaders();

        projection_matrix[15] = 1;

        enum properties = [
            "num_tev_stages",
            "in_color_a",
            "in_color_b",
            "in_color_c",
            "in_color_d",
            "in_alfa_a",
            "in_alfa_b",
            "in_alfa_c",
            "in_alfa_d",
            "color_dest",
            "alfa_dest",
            "bias_color",
            "scale_color",
            "bias_alfa",
            "scale_alfa",
            "reg0",
            "reg1",
            "reg2",
            "reg3",
            "ras",
            "konst_a",
            "konst_b",
            "konst_c",
            "konst_d",
        ];

        // losing my mind over this
        static foreach (prop; properties) {{
            auto ix = glGetProgramResourceIndex(gl_program, GL_UNIFORM, prop.ptr);
            GLenum[] props = [ GL_ARRAY_STRIDE, GL_OFFSET ];
            GLint[2] values = [0, 0];
            glGetProgramResourceiv(gl_program, GL_UNIFORM, ix, 2, props.ptr, 2,null, values.ptr);
            log_hollywood("%s offset: %d, stride: %d %d", prop, values[1], values[0], mixin("TevConfig." ~ prop ~ ".offsetof"));
        }}
        // auto ix = glGetProgramResourceIndex(gl_program, GL_UNIFORM, "in_color_a");
        // GLenum[] props = [ GL_ARRAY_STRIDE, GL_OFFSET ];
        // GLint[2] values = [0, 0];
        // glGetProgramResourceiv(gl_program, GL_UNIFORM, ix, 2, props.ptr, 2,null, values.ptr);
        // log_hollywood("offset: %d, stride: %d", values[1], values[0]);
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    void write_GX_FIFO(T)(T value, int offset) {
        fifo_write_ptr += T.sizeof;
        while (fifo_write_ptr >= fifo_base_end) {
            fifo_write_ptr -= (fifo_base_end - fifo_base_start);
            fifo_wrapped = true;
        }

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
                    log_hollywood("Expecting %d vertices", number_of_expected_vertices);
                    state = State.WaitingForVertexData;
                } else {
                    error_hollywood("Unexpected GX FIFO write");
                }

                break;
            
            case State.WaitingForVertexData:
                // static if (is(T == u32)) {
                    shape_data[number_of_received_writes_for_shape] = cast(u32) value;
                    number_of_received_writes_for_shape++;

                    if (number_of_received_writes_for_shape == number_of_expected_writes_for_shape) {
                        process_new_shape();
                        state = State.WaitingForCommand;
                        number_of_received_writes_for_shape = 0;
                    }
                // } else {
                    // error_hollywood("Unexpected GX FIFO write");
                // }

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
            case GXFifoCommand.NoOp:              break;
            
            case GXFifoCommand.DrawQuads | 0: .. case GXFifoCommand.DrawQuads | 7:         
                current_draw_command = GXFifoCommand.DrawQuads;
                current_vat = (cast(int) command).bits(0, 2);
                state = State.WaitingForNumberOfVertices;
                break;
            
            case GXFifoCommand.DrawTriangleFan | 0: .. case GXFifoCommand.DrawTriangleFan | 7:
                current_draw_command = GXFifoCommand.DrawTriangleFan;
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
            
            case 0x00:
                tev_config.num_tev_stages = bp_data.bits(10, 13) + 1;
                log_hollywood("GEN_MODE: %08x", bp_data);
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

            case 0x10: .. case 0x1f:
                log_hollywood("IND_CMD%x: %08x (tev indirect %d)", bp_register - 0x10, bp_data, bp_register - 0x10);
                break;
            
            case 0x28: .. case 0x2f:
                ras_color[bp_register - 0x28] = cast(RasChannelId) bp_data.bits(19, 21);
                break;
            
            case 0xc0: .. case 0xdf:
                if (bp_register.bit(0)) {
                    log_hollywood("TEV_ALPHA_ENV_%x: %08x (tev op 1) at pc 0x%08x", bp_register - 0xc1, bp_data, mem.cpu.state.pc);
                    int idx = (bp_register - 0xc1) / 2;
                    tev_config.in_alfa_a[idx] = bp_data.bits(13, 15);
                    tev_config.in_alfa_b[idx] = bp_data.bits(10, 12);
                    tev_config.in_alfa_c[idx] = bp_data.bits(7, 9);
                    tev_config.in_alfa_d[idx] = bp_data.bits(4, 6);
                    tev_config.bias_alfa[idx] = 
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5;
                    tev_config.alfa_dest[idx] = bp_data.bits(22, 23);

                    if (bp_data.bits(16, 17) == 3) {
                        error_hollywood("Invalid bias");
                    }

                    tev_config.scale_alfa[idx] = 
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5;
                    
                    if (bp_data.bits(18, 19) > 3) {
                        error_hollywood("Invalid scale");
                    }
                } else {
                    log_hollywood("TEV_COLOR_ENV_%x: %08x (tev op 0) at pc 0x%08x", bp_register - 0xc0, bp_data, mem.cpu.state.pc);
                    int idx = (bp_register - 0xc0) / 2;
                    tev_config.in_color_a[idx] = bp_data.bits(12, 15);
                    tev_config.in_color_b[idx] = bp_data.bits(8, 11);
                    tev_config.in_color_c[idx] = bp_data.bits(4, 7);
                    tev_config.in_color_d[idx] = bp_data.bits(0, 3);
                    tev_config.bias_color[idx] = 
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5;
                    tev_config.color_dest[idx] = bp_data.bits(22, 23);

                    if (bp_data.bits(16, 17) == 3) {
                        error_hollywood("Invalid bias");
                    }

                    tev_config.scale_color[idx] = 
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5;
                }
                break;
            
            case 0xe0: .. case 0xe7:
                if (bp_register.bit(0)) {
                    int idx = (bp_register - 0xe1) / 2;
                    // i dont trust D's memory layout
                    final switch (idx) {
                    case 0: 
                        tev_config.reg0[2] = bp_data.bits(0,   7) / 255.0f; 
                        tev_config.reg0[1] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    case 1:
                        tev_config.reg1[2] = bp_data.bits(0,   7) / 255.0f;
                        tev_config.reg1[1] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    case 2:
                        tev_config.reg2[2] = bp_data.bits(0,   7) / 255.0f;
                        tev_config.reg2[1] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    case 3:
                        tev_config.reg3[2] = bp_data.bits(0,   7) / 255.0f;
                        tev_config.reg3[1] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    }
                } else {
                    int idx = (bp_register - 0xe0) / 2;
                    // i dont trust D's memory layout
                    final switch (idx) {
                    case 0: 
                        tev_config.reg0[0] = bp_data.bits(0,   7) / 255.0f; 
                        tev_config.reg0[3] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    case 1:
                        tev_config.reg1[0] = bp_data.bits(0,   7) / 255.0f;
                        tev_config.reg1[3] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    case 2:
                        tev_config.reg2[0] = bp_data.bits(0,   7) / 255.0f;
                        tev_config.reg2[3] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    case 3:
                        tev_config.reg3[0] = bp_data.bits(0,   7) / 255.0f;
                        tev_config.reg3[3] = bp_data.bits(12, 19) / 255.0f;
                        break;
                    }
                }
                break;
       
            case 0xee: .. case 0xf1:
                log_hollywood("TEV_FOG_PARAM_%x: %08x", bp_register - 0xee, bp_data);
                break;

            case 0xf3:
                log_hollywood("TEV_ALPHAFUNC: %08x", bp_data);
                break;
            
            case 0xf4: .. case 0xf5:
                log_hollywood("TEV_Z_ENV_%x: %08x", bp_register - 0xf4, bp_data);
                break;
            
            case 0xf6: .. case 0xfd:
                log_hollywood("TEV_KSEL_%x: %08x", bp_register - 0xf6, bp_data);
                break;

            case 0x80: .. case 0x83:
                texture_descriptors[bp_register - 0x80].wrap_s = cast(TextureWrap) bp_data.bits(0, 1);
                texture_descriptors[bp_register - 0x80].wrap_t = cast(TextureWrap) bp_data.bits(2, 3);
                break;

            case 0xa0: .. case 0xa3:
                texture_descriptors[bp_register - 0xa0 + 4].wrap_s = cast(TextureWrap) bp_data.bits(0, 1);
                texture_descriptors[bp_register - 0xa0 + 4].wrap_t = cast(TextureWrap) bp_data.bits(2, 3);
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
            
            case 0x60: .. case 0x67:
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
            
            case 0x70: .. case 0x77:
                auto vat = &vats[register - 0x70];

                vat.position_count = value.bit(0) ? 3 : 2;
                vat.position_format = cast(CoordFormat) value.bits(1, 3);
                vat.position_shift = value.bits(4, 8);
                vat.normal_count = value.bit(9) ? 9 : 3;
                vat.normal_format = cast(NormalFormat) value.bits(10, 12);
                vat.color_count[0] = value.bit(13) ? 4 : 3;
                vat.color_format[0] = cast(ColorFormat) value.bits(14, 16);
                vat.color_count[1] = value.bit(17) ? 4 : 3;
                vat.color_format[1] = cast(ColorFormat) value.bits(18, 20);
                vat.texcoord_count[0] = value.bit(21) ? 2 : 1;
                vat.texcoord_format[0] = cast(CoordFormat) value.bits(22, 24);
                vat.texcoord_shift[0] = value.bits(25, 29);
                assert(value.bits(30, 31) == 0b01);
                
                break;
            
            case 0x80: .. case 0x87:
                auto vat = &vats[register - 0x80];
                
                vat.texcoord_count[1] = value.bit(0) ? 2 : 1;
                vat.texcoord_format[1] = cast(CoordFormat) value.bits(1, 3);
                vat.texcoord_shift[1] = value.bits(4, 8);
                vat.texcoord_count[2] = value.bit(9) ? 2 : 1;
                vat.texcoord_format[2] = cast(CoordFormat) value.bits(10, 12);
                vat.texcoord_shift[2] = value.bits(13, 17);
                vat.texcoord_count[3] = value.bit(18) ? 2 : 1;
                vat.texcoord_format[3] = cast(CoordFormat) value.bits(19, 21);
                vat.texcoord_shift[3] = value.bits(22, 26);
                vat.texcoord_count[4] = value.bit(27) ? 2 : 1;
                vat.texcoord_format[4] = cast(CoordFormat) value.bits(28, 30);                

                break;
            
            case 0x90: .. case 0x97:
                auto vat = &vats[register - 0x90];
                
                vat.texcoord_shift[4] = value.bits(0, 4);
                vat.texcoord_count[5] = value.bit(5) ? 2 : 1;
                vat.texcoord_format[5] = cast(CoordFormat) value.bits(6, 8);
                vat.texcoord_shift[5] = value.bits(9, 13);
                vat.texcoord_count[6] = value.bit(14) ? 2 : 1;
                vat.texcoord_format[6] = cast(CoordFormat) value.bits(15, 17);
                vat.texcoord_shift[6] = value.bits(18, 22);
                vat.texcoord_count[7] = value.bit(23) ? 2 : 1;
                vat.texcoord_format[7] = cast(CoordFormat) value.bits(24, 26);
                vat.texcoord_shift[7] = value.bits(27, 31);
          
                break;

            default:
                log_hollywood("Unimplemented: CP register %02x", register);
                break;
        }
    }

    private int size_of_incoming_vertex(int vat_idx) {
        auto vcd = &vertex_descriptors[vat_idx];
        auto vat = &vats[vat_idx];

        int size = 0;

        if (vcd.position_location != VertexAttributeLocation.NotPresent) {
            size += vat.position_count;
        }

        if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
            // error_hollywood("Normal location not implemented");
            size += vat.normal_count;
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
                size += vat.color_count[i];
            }
        }

        for (int i = 0; i < 8; i++) {
            if (vcd.texcoord_location[i] != VertexAttributeLocation.NotPresent) {
                size += vat.texcoord_count[i];
            }
        }

        log_hollywood("VCDILF: %s", *vcd);
        log_hollywood("VATDILF: %s", *vat);

        return size;
    }

    private void handle_new_transform_unit_write(u16 register, u32 value) {
        
        switch (register) {
            case 0x1018:
                log_hollywood("geometry_matrix: %08x", value);
                // TODO: wtf is a geometry matrix
                texture_descriptors[0].tex_matrix_slot = value.bits(6, 11);
                texture_descriptors[1].tex_matrix_slot = value.bits(12, 17);
                texture_descriptors[2].tex_matrix_slot = value.bits(18, 23);
                texture_descriptors[3].tex_matrix_slot = value.bits(24, 29);
                break;

            case 0x1019:
                texture_descriptors[4].tex_matrix_slot = value.bits(0, 5);
                texture_descriptors[5].tex_matrix_slot = value.bits(6, 11);
                texture_descriptors[6].tex_matrix_slot = value.bits(12, 17);
                texture_descriptors[7].tex_matrix_slot = value.bits(18, 23);
                break;

            case 0x101a: log_hollywood("viewport[0]: %f", force_cast!float(value)); break;
            case 0x101b: log_hollywood("viewport[1]: %f", force_cast!float(value)); break;
            case 0x101c: log_hollywood("viewport[2]: %f", force_cast!float(value)); break;
            case 0x101d: log_hollywood("viewport[3]: %f", force_cast!float(value)); break;
            case 0x101e: log_hollywood("viewport[4]: %f", force_cast!float(value)); break;
            case 0x101f: log_hollywood("viewport[5]: %f", force_cast!float(value)); break;
            case 0x1020: .. case 0x1025:
                projection_matrix_parameters[register - 0x1020] = force_cast!float(value);
                recalculate_projection_matrix();
                break;

            case 0x1026: 
                if (value <= 1) {
                    log_hollywood("projection_mode: %d", value);
                    projection_mode = cast(ProjectionMode) value;
                } else {
                    error_hollywood("Invalid projection mode");
                }

                recalculate_projection_matrix();
                break;
            
            case 0x1040: .. case 0x1047:
                log_hollywood("BIGREG %x: %08x", register, value);
                break;
            case 0x0000: .. case 0x00ff:
                general_matrix_ram[register] = force_cast!float(value);
                break;
            
            case 0x0500: .. case 0x05ff:
                dt_texture_matrix_ram[register - 0x500] = force_cast!float(value);
                break;
            
            case 0x1050: .. case 0x1057:
                int idx = register - 0x1050;

                bool normal_enable = value.bit(7); // not sure yet
                int mtx_slot = value.bits(0, 5);

                texture_descriptors[idx].dualtex_matrix_slot = mtx_slot;
                texture_descriptors[idx].dualtex_normal_enable = normal_enable;
                break;
            
            case 0x100c:
                color_0_global = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];

                log_hollywood("color_0_global: %s %x", color_0_global,value);
                break;
            
            case 0x100d:
                color_1_global = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                break;

            default:
                log_hollywood("Unimplemented: Transform unit register %04x = %08x", register, value);
                break;
        }
    }

    private void recalculate_projection_matrix() {
        alias p = projection_matrix_parameters;
    
        final switch (projection_mode) {
            case ProjectionMode.Perspective:
                projection_matrix = [
                    p[0], 0,    0,     0,
                    0,    p[2], 0,     0,
                    p[1], p[3], p[4], -1,
                    0,    0,    p[5],  0
                ];
                break;
            
            case ProjectionMode.Orthographic:
                projection_matrix = [
                    p[0], 0,    0,    0,
                    0,    p[2], 0,    0,
                    0,    0,    p[4], 0,
                    p[1], p[3], p[5], 1
                ];
                break;
        }
    }

    private float dequantize_coord(u32 value, CoordFormat format, int shift) {
        final switch (format) {
            case CoordFormat.U8:
                return cast(float) ((cast(u8) value) << shift);
            
            case CoordFormat.S8:
                return cast(float) (sext_32((cast(s8) value), 8) << shift);
            
            case CoordFormat.U16:
                return cast(float) ((cast(u16) value) << shift);
            
            case CoordFormat.S16:
                return cast(float) (sext_32((cast(s16) value), 16) << shift);
            
            case CoordFormat.F32:
                return force_cast!float(value);
        }
    }

    private float[4] dequantize_color(u32 value, ColorFormat format, int index) {
        final switch (format) {
            case ColorFormat.RGB565:
                return [
                    (cast(float) (value.bits(0, 4) << 3)) / 0xff,
                    (cast(float) (value.bits(5, 10) << 2)) / 0xff,
                    (cast(float) (value.bits(11, 15) << 3)) / 0xff,
                    1.0
                ];
            
            case ColorFormat.RGB888:
                return [
                    (cast(float) (value.bits(0, 7))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    1.0
                ];
            
            case ColorFormat.RGB888x:
                return [
                    (cast(float) (value.bits(0, 7))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    1.0
                ];
            
            case ColorFormat.RGBA4444:
                return [
                    (cast(float) (value.bits(0, 3) << 4)) / 0xff,
                    (cast(float) (value.bits(4, 7) << 4)) / 0xff,
                    (cast(float) (value.bits(8, 11) << 4)) / 0xff,
                    (cast(float) (value.bits(12, 15) << 4)) / 0xff
                ];
            
            case ColorFormat.RGBA6666:
                return [
                    (cast(float) (value.bits(0, 5) << 2)) / 0xff,
                    (cast(float) (value.bits(6, 11) << 2)) / 0xff,
                    (cast(float) (value.bits(12, 17) << 2)) / 0xff,
                    (cast(float) (value.bits(18, 23) << 2)) / 0xff
                ];
            
            case ColorFormat.RGBA8888:
                return [
                    (cast(float) (value.bits(0, 7))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    (cast(float) (value.bits(24, 31))) / 0xff
                ];
        }
    }

    private void process_new_shape() {
        glUseProgram(gl_program);

        ShapeGroup shape_group;
        shape_group.shapes = [];
        shape_group.textured = false;
        shape_group.position_matrix = general_matrix_ram[0 .. 12]; // ????
        shape_group.projection_matrix = projection_matrix;

        int offset = 0;
        Vertex[] vertices;
        for (int i = 0; i < number_of_expected_vertices; i++) {
            Vertex v;
            
            auto vcd = &vertex_descriptors[current_vat];
            auto vat = &vats[current_vat];

            if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
                error_hollywood("Matrix location not implemented");
            }

            for (int j = 0; j < 8; j++) {
                if (vcd.texcoord_matrix_location[j] != VertexAttributeLocation.NotPresent) {
                    error_hollywood("Matrix location not implemented");
                }
            }
            
            if (vcd.position_location != VertexAttributeLocation.NotPresent) {
                for (int j = 0; j < vat.position_count; j++) {
                    v.position[j] = dequantize_coord(shape_data[offset], vat.position_format, vat.position_shift);
                    offset++;
                }
            }

            if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
                // error_hollywood("Normal location not implemented");
            }

            for (int j = 0; j < 2; j++) {
                if (vcd.color_location[j] != VertexAttributeLocation.NotPresent) {
                    v.color[j] = dequantize_color(shape_data[offset], vat.color_format[j], 0);

                    if (vat.color_count[j] == 3) {
                        v.color[j][3] = 1.0;
                    }

                    offset += vat.color_count[j];
                }
            }

            // for (int j = 0; j < 8; j++) {
            for (int j = 0; j < 8; j++) { 
                if (vcd.texcoord_location[j] == VertexAttributeLocation.Direct) {
                    if (j != 0) {
                        offset += vat.texcoord_count[j];
                        continue;
                    }

                    for (int k = 0; k < vat.texcoord_count[j]; k++) {
                        v.texcoord[k] = dequantize_coord(shape_data[offset], vat.texcoord_format[j], vat.texcoord_shift[j]);
                        offset++;
                    }

                    if (i == 0) {
                        shape_group.texture[j].data = load_texture(texture_descriptors[j], mem).ptr;
                        shape_group.texture[j].width = texture_descriptors[j].width;
                        shape_group.texture[j].height = texture_descriptors[j].height;
                        shape_group.texture[j].wrap_s = texture_descriptors[j].wrap_s;
                        shape_group.texture[j].wrap_t = texture_descriptors[j].wrap_t;
                        shape_group.texture[j].dualtex_matrix = 
                            dt_texture_matrix_ram[texture_descriptors[j].dualtex_matrix_slot * 4 + 0 .. 
                            texture_descriptors[j].dualtex_matrix_slot * 4 + 12];
                        shape_group.texture[j].tex_matrix = 
                            general_matrix_ram[texture_descriptors[j].tex_matrix_slot * 4 + 0 ..
                            texture_descriptors[j].tex_matrix_slot * 4 + 12];

                        shape_group.texture[j].dualtex_normal_enable = texture_descriptors[j].dualtex_normal_enable;

                        shape_group.textured = true;
                    }
                }
            }

            vertices ~= v;
        }

        shape_group.tev_config = tev_config;

        for (int i = 0; i < 16; i++) {
            switch (ras_color[i]) {
                case RasChannelId.Color0: shape_group.tev_config.ras[i] = color_0_global; break;
                default: log_hollywood("unimpelmented ras: %x", ras_color[i]); break;
            }
        }
        shape_group.tev_config.konst_a = [1.0f, 1.0f, 0.0f, 1.0f];

        switch (current_draw_command) {
            case GXFifoCommand.DrawQuads:
                for (int i = 0; i < vertices.length; i += 4) {
                    Shape shape;
                    shape.vertices = vertices[i .. i + 3];
                    shape_group.shapes ~= shape;
                }

                for (int i = 0; i < vertices.length; i += 4) {
                    Shape shape;
                    shape.vertices = [vertices[i + 0], vertices[i + 2], vertices[i + 3]];
                    shape_group.shapes ~= shape;
                }
                break;
            
            case GXFifoCommand.DrawTriangleFan:
                for (int i = 1; i < vertices.length - 2; i++) {
                    Shape shape;
                    shape.vertices = [vertices[0], vertices[i + 1], vertices[i + 2]];
                    shape_group.shapes ~= shape;
                }
                break;
            
            default: error_hollywood("Unimplemented draw command: %s", current_draw_command);
        }
        
        shape_groups ~= shape_group;
    }

    bool shit = false;

    public void draw() {
        draw_shape_groups(shape_groups);
    }

    void draw_shape_groups(ShapeGroup[] shape_groups) {
        if (shape_groups.length == 0) {
            return;
        }

        glUseProgram(gl_program);
        glClearColor(0, 0, 0, 1); 
        // glClearDepth(1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_ALWAYS);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        gl_object_manager.deallocate_all_objects();
        

        // if (mem.cpu.interrupt_controller.ipc.scheduler.get_current_time_relative_to_cpu() >= 0x00000003e983c14) {
        //     // for (int i = 0; i < 10; i++) {
        //     //     uint x = gl_object_manager.
        //     // }
            
        //     return;
        // }

        // if (!shit) { shit = true; return; }
        // shit = false;
        
        int texnum = 0; int i = 0;
        log_hollywood("Rendering %d shape groups", shape_groups.length);
        log_hollywood("Amongus projection matrix: %s", projection_matrix);
        foreach (ShapeGroup shape_group; shape_groups) {
            draw_shape_group(shape_group, texnum);
            debug_drawn_shape_groups ~= shape_group;
        }

        this.shape_groups = [];
    }

    void draw_shape_group(ShapeGroup shape_group, int texnum) {
        if (shape_group.textured) {
            GLuint texture_id = gl_object_manager.allocate_texture_object();

            // "Bind" the newly created texture : all future texture functions will modify this texture
            glBindTexture(GL_TEXTURE_2D, texture_id);

            // Give the image to OpenGL
            // log_hollywood("projection color: %s", shape.texture[0]);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, cast(GLint) shape_group.texture[0].height, cast(GLint) shape_group.texture[0].width, 0, GL_BGRA, GL_UNSIGNED_BYTE, shape_group.texture[0].data);

            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

            // final switch (shape.texture[0].wrap_s) {
            //     case TextureWrap.Clamp:
            //         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            //         break;
                
            //     case TextureWrap.Repeat:
            //         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            //         break;
                
            //     case TextureWrap.Mirror:
            //         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_MIRRORED_REPEAT);
            //         break;
            // }

            // final switch (shape.texture[0].wrap_t) {
            //     case TextureWrap.Clamp:
            //         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            //         break;
                
            //     case TextureWrap.Repeat:
            //         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            //         break;
                
            //     case TextureWrap.Mirror:
            //         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_MIRRORED_REPEAT);
            //         break;
            // }

            glUniform1i(glGetUniformLocation(gl_program, "wiiscreen"), texnum);
            glActiveTexture(GL_TEXTURE0 + texnum);
            glBindTexture(GL_TEXTURE_2D, texture_id);
            
            texnum++;
        } else {
            return;
        }
    
        submit_shape_group_to_opengl(shape_group);
    }

    void submit_shape_group_to_opengl(ShapeGroup shape_group) {
        // log_hollywood("Submitting shape group to OpenGL (%d): %s", shape_group.shapes.length, shape_group);
        // log_hollywood("pointer data: %x %x %x", shape_group.shapes.ptr, shape_group.shapes[0].vertices.ptr, shape_group.shapes[0].vertices[2].position.ptr);

        uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
        uint vertex_buffer_object = gl_object_manager.allocate_vertex_buffer_object();
        glBindVertexArray(vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object);
        glBufferData(GL_ARRAY_BUFFER, 40 * shape_group.shapes.length * GLfloat.sizeof * 3, shape_group.shapes.ptr, GL_STATIC_DRAW);

        auto position_location = glGetAttribLocation(gl_program, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, 40 * float.sizeof, cast(void*) 0);

        auto normal_location = glGetAttribLocation(gl_program, "normal");
        glEnableVertexAttribArray(normal_location);
        glVertexAttribPointer(normal_location, 3, GL_FLOAT, GL_FALSE, 40 * float.sizeof, cast(void*) (3 * float.sizeof));

        auto texcoord_location = glGetAttribLocation(gl_program, "texcoord");
        glEnableVertexAttribArray(texcoord_location);
        glVertexAttribPointer(texcoord_location, 2, GL_FLOAT, GL_FALSE, 40 * float.sizeof, cast(void*) (6 * float.sizeof));

        auto color_location = glGetAttribLocation(gl_program, "in_color");
        glEnableVertexAttribArray(color_location);
        glVertexAttribPointer(color_location, 4, GL_FLOAT, GL_FALSE, 40 * float.sizeof, cast(void*) (8 * float.sizeof));

        glUniformMatrix4x3fv(glGetUniformLocation(gl_program, "position_matrix"), 1, GL_TRUE,  shape_group.position_matrix.ptr);
        glUniformMatrix4x3fv(glGetUniformLocation(gl_program, "texture_matrix"),  1, GL_TRUE,  shape_group.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv  (glGetUniformLocation(gl_program, "MVP"),             1, GL_FALSE, shape_group.projection_matrix.ptr);

        uint ubo = gl_object_manager.allocate_uniform_buffer_object();
        glBindBuffer(GL_UNIFORM_BUFFER, ubo);
        glBufferData(GL_UNIFORM_BUFFER, TevConfig.sizeof, &shape_group.tev_config, GL_STATIC_DRAW);
        glUniformBlockBinding(gl_program, glGetUniformBlockIndex(gl_program, "TevConfig"), 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, ubo);

        glDrawArrays(GL_TRIANGLES, 0, cast(int) shape_group.shapes.length * 3);

        log_hollywood("Drawing shape");
    }

    void load_shaders() {
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
            import core.stdc.stdlib;
            import std.string;
            
            char* info_log = cast(char*) malloc(10000000);
            int info_log_length;

            glGetShaderInfoLog(fragment_shader, 10000000, &info_log_length, cast(char*) info_log);
            error_hollywood("Fragment shader compilation error: %s", info_log.fromStringz);
        } 
        
        gl_program = glCreateProgram();

        glBindAttribLocation(gl_program, 0, "in_Position");
            
        glAttachShader(gl_program, vertex_shader);
        glAttachShader(gl_program, fragment_shader);
        
        glLinkProgram(gl_program);
        glUseProgram(gl_program);
    }

    u32 fifo_base_start;
    u32 fifo_base_end;
    u32 fifo_write_ptr;
    bool fifo_wrapped = false;

    u8 read_FIFO_BASE_START(int target_byte) {
        return fifo_base_start.get_byte(target_byte);
    }

    void write_FIFO_BASE_START(int target_byte, u8 value) {
        log_broadway("write FIFO_BASE_START[%d] = %02x", target_byte, value);
        fifo_base_start = fifo_base_start.set_byte(target_byte, value);
    }

    u8 read_FIFO_BASE_END(int target_byte) {
        return fifo_base_end.get_byte(target_byte);
    }

    void write_FIFO_BASE_END(int target_byte, u8 value) {
        log_broadway("write FIFO_BASE_END[%d] = %02x", target_byte, value);
        fifo_base_end = fifo_base_end.set_byte(target_byte, value);
    }

    u8 read_FIFO_WRITE_PTR(int target_byte) {
        log_broadway("read FIFO_WRITE_PTR[%d] = %02x", target_byte, fifo_write_ptr.get_byte(target_byte));
        u8 return_value = fifo_write_ptr.get_byte(target_byte);
    
        if (target_byte == 3) {
            return_value &= 0x1f;
            return_value |= fifo_wrapped << 5;
        }

        return return_value;
    }

    void write_FIFO_WRITE_PTR(int target_byte, u8 value) {
        log_broadway("write FIFO_WRITE_PTR[%d] = %02x", target_byte, value);
        fifo_write_ptr = fifo_write_ptr.set_byte(target_byte, value);
        fifo_write_ptr &= 0x1fffffff;

        if (target_byte == 3) {
            fifo_wrapped = value.bit(5);
        }
    }

    ShapeGroup[] debug_drawn_shape_groups;

    ShapeGroup[] debug_get_drawn_shape_groups() {
        ShapeGroup[] return_value;
        for (int i = 0; i < debug_drawn_shape_groups.length; i++) {
            return_value ~= debug_drawn_shape_groups[i];
        }
    
        debug_drawn_shape_groups = [];
        return return_value;
    }

    void debug_draw_shape_group(ShapeGroup shape_group) {
        submit_shape_group_to_opengl(shape_group);
    }

    void debug_redraw(ShapeGroup[] shape_groups) {
        draw_shape_groups(shape_groups);
    }

    void debug_reload_shaders() {
        load_shaders();
    }
}