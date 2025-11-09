module emu.hw.hollywood.hollywood;

import bindbc.opengl;
import emu.hw.cp.cp;
import emu.hw.hollywood.blitting_processor;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.texture;
import emu.hw.pe.pe;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import std.file;
import util.bitop;
import util.force_cast;
import util.log;
import util.number;
import util.page_allocator;
import util.ringbuffer;

alias Shape = Hollywood.Shape;
alias ShapeGroup = Hollywood.ShapeGroup;
alias Texture = Hollywood.Texture;

final class Hollywood {
    enum GXFifoCommand {
        BlittingProcessor = 0x61,
        CommandProcessor  = 0x08,
        TransformUnit     = 0x10,

        VSInvalidate      = 0x48,
        NoOp              = 0x00,

        DrawQuads         = 0x80,
        DrawTriangleFan   = 0xA0,
        DrawTriangleStrip = 0x98,
        DrawLines         = 0xA8,

        DisplayList       = 0x40,
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
        WaitingForDisplayListAddress,
        WaitingForDisplayListSize,
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
        float[2][8] texcoord;
        float[4][2] color;
    }

    struct Texture {
        Color* data;
        size_t width;
        size_t height;
        TextureWrap wrap_s;
        TextureWrap wrap_t;

        float[12] dualtex_matrix;
        float[12] tex_matrix;
        bool normalize_before_dualtex;
    }

    struct ShapeGroup {    
        float[12] position_matrix;
        float[16] projection_matrix;
        Texture[8] texture;
        TevConfig tev_config;
        VertexConfig vertex_config;
        bool textured;
        int enabled_textures_bitmap;

        PageAllocator!Shape shapes;
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

    enum MaterialSource {
        FromGlobal = 0,
        FromVertex = 1,
    }

    struct ColorConfig {
        MaterialSource material_src;
    }

    ColorConfig[2] color_configs;

    struct GlAlignedU32 {
        u32 value;
        u32[3] padding;
        alias value this;

        void opAssign(u32 value) {
            this.value = value;
        }
    }

    struct GlAlignedFloat {
        float value;
        alias value this;

        void opAssign(float value) {
            this.value = value;
        }
    }

    struct TevStage {
        u32 in_color_a;
        u32 in_color_b;
        u32 in_color_c;
        u32 in_color_d;
        u32 in_alfa_a;
        u32 in_alfa_b;
        u32 in_alfa_c;
        u32 in_alfa_d;
        u32 color_dest;
        u32 alfa_dest;
        float bias_color;
        float scale_color;
        float bias_alfa;
        float scale_alfa;
        u32 ras_channel_id;
        u32 ras_swap_table_index;
        u32 tex_swap_table_index;
        u32 texmap;
        u32 texcoord;
        u32 texmap_enable;
    }

    struct TevConfig {
        align(1):
        TevStage[16] stages;

        GlAlignedFloat[4] reg0;
        GlAlignedFloat[4] reg1;
        GlAlignedFloat[4] reg2;
        GlAlignedFloat[4] reg3;

        int num_tev_stages;
        u64 swap_tables; // 8 * 4 
    }

    alias GLBool = u32;

    struct TexConfig {
        align(1):
        float[12] dualtex_matrix;
        float[12] tex_matrix;
        GLBool    normalize_before_dualtex;
        u32       texcoord_source;
        u32[2]    padding2;
    }

    struct VertexConfig {
        align(1):
        TexConfig[8] tex_configs;
        int end; // used to verify the size of tex_configs[8] by getting the offset of end
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

    PageAllocator!ShapeGroup shape_groups;
    PageAllocator!Vertex vertex_allocator;
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
    private int number_of_expected_bytes_for_shape;
    private int number_of_received_bytes_for_shape;
    
    private int bazinga;

    private GLfloat[16] projection_matrix = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    private GLfloat[6]  projection_matrix_parameters;
    private float[256] general_matrix_ram;
    private float[256] dt_texture_matrix_ram;

    private float[4][2] color_global;

    private GLuint gl_program;

    private GlObjectManager gl_object_manager;
    
    private u32 display_list_address;
    private u32 display_list_size;

    u32[16] array_bases;
    u32[16] array_strides;

    u16 enabled_textures;
    int[8] texture_uniform_locations;

    struct FifoDebugValue {
        u64 value;
        State state;
    }

    RingBuffer!FifoDebugValue fifo_debug_history;
    RingBuffer!u8 pending_fifo_data;

    this() {
        pending_fifo_data = new RingBuffer!u8(0x100000);
        fifo_debug_history = new RingBuffer!FifoDebugValue(100);
        shape_groups = PageAllocator!ShapeGroup(0);
        vertex_allocator = PageAllocator!Vertex(0);
        log_hollywood("Hollywood constructor");
    }

    void init_opengl() {
        blitting_processor = new BlittingProcessor();
        gl_object_manager = new GlObjectManager();

        state = State.WaitingForCommand;

        load_shaders();

        projection_matrix[15] = 1;

        enum tev_properties = [
            "num_tev_stages",
            "stages",
            "reg0",
            "reg1",
            "reg2",
            "reg3",
        ];

        // losing my mind over this
        static foreach (prop; tev_properties) {{
            auto ix = glGetProgramResourceIndex(gl_program, GL_UNIFORM, prop.ptr);
            GLenum[] props = [ GL_ARRAY_STRIDE, GL_OFFSET ];
            GLint[2] values = [0, 0];
            glGetProgramResourceiv(gl_program, GL_UNIFORM, ix, 2, props.ptr, 2,null, values.ptr);
            log_hollywood("%s offset: %d, stride: %d %d", prop, values[1], values[0], mixin("TevConfig." ~ prop ~ ".offsetof"));
        }}

        enum vertex_properties = [
            "end"
        ];

        static foreach (prop; vertex_properties) {{
            auto ix = glGetProgramResourceIndex(gl_program, GL_UNIFORM, prop.ptr);
            GLenum[] props = [ GL_ARRAY_STRIDE, GL_OFFSET ];
            GLint[2] values = [0, 0];
            glGetProgramResourceiv(gl_program, GL_UNIFORM, ix, 2, props.ptr, 2,null, values.ptr);
            log_hollywood("%s offset: %d, stride: %d %d", prop, values[1], values[0], mixin("VertexConfig." ~ prop ~ ".offsetof"));
        }}
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    // hank do not abbreviate CommandProcessor, haaankkkkkkkk!!!!!!
    CommandProcessor command_processor;
    void connect_command_processor(CommandProcessor command_processor) {
        this.command_processor = command_processor;
    }

    PixelEngine pixel_engine;
    void connect_pixel_engine(PixelEngine pixel_engine) {
        this.pixel_engine = pixel_engine;
    }

    Scheduler scheduler;
    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void write_GX_FIFO(T)(T value, int offset) {
        // if (!command_processor.fifos_linked) {
        //     return;
        // }

        log_hollywood("GX FIFO write: %08x %d %d %x %x", value, offset, T.sizeof, mem.cpu.state.pc, mem.cpu.state.lr);
        fifo_write_ptr += T.sizeof;
        while (fifo_write_ptr >= fifo_base_end) {
            fifo_write_ptr -= (fifo_base_end - fifo_base_start);
            fifo_wrapped = true;
        }

        process_fifo_write(value, offset);
    }

    T read_from_pending_fifo_data(T)() {
        if (T.sizeof > pending_fifo_data.get_size()) {
            error_hollywood("Pending FIFO data does not have enough data. %x requested, %x available", T.sizeof, pending_fifo_data.get_size());
        }

        T value;
        static foreach(i; 0 .. T.sizeof) {
            value = cast(T) value.set_byte(T.sizeof - i - 1, pending_fifo_data.remove());
        }

        log_hollywood("read_from_pending_fifo_data: %x %x", value, pending_fifo_data.get_size());

        return value;
    }

    void process_fifo_write(T)(T value, int offset) {
        fifo_debug_history.add_overwrite(FifoDebugValue(value, state));

        static foreach(i; 0 .. T.sizeof) {
            log_hollywood("pending_fifo_data[%d] = %02x", i, value.get_byte(i));
            pending_fifo_data.add(value.get_byte(T.sizeof - i - 1));
        }

        log_hollywood("GX FIFO LOG: %08x %d %s", value, offset, state);

        bool handled = false;
        do {
            handled = false;
            final switch (state) {
                case State.WaitingForCommand:
                    if (pending_fifo_data.get_size() >= 1) {
                        handle_new_command(read_from_pending_fifo_data!u8);
                        handled = true;
                    }

                    break;

                case State.WaitingForBPWrite:
                    if (pending_fifo_data.get_size() >= 4) {
                        handle_new_bp_write(read_from_pending_fifo_data!u32);
                        state = State.WaitingForCommand;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForCPReg:
                    if (pending_fifo_data.get_size() >= 1) {
                        cp_register = read_from_pending_fifo_data!u8;
                        state = State.WaitingForCPData;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForCPData:
                    if (pending_fifo_data.get_size() >= 4) {
                        handle_new_cp_write(cp_register, read_from_pending_fifo_data!u32);
                        state = State.WaitingForCommand;
                        handled = true;
                    }

                    break;

                case State.WaitingForTransformUnitDescriptor:
                    if (pending_fifo_data.get_size() >= 4) {
                        u32 data         = read_from_pending_fifo_data!u32;
                        xf_register       = cast(u16)  data.bits(0, 15);
                        xf_data_remaining = cast(u16) (data.bits(16, 31) + 1);

                        state = State.WaitingForTransformUnitData;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForTransformUnitData:
                    if (pending_fifo_data.get_size() >= 4) {
                        handle_new_transform_unit_write(xf_register, read_from_pending_fifo_data!u32);

                        xf_data_remaining -= 1;
                        xf_register += 1;

                        if (xf_data_remaining == 0) {
                            state = State.WaitingForCommand;
                        }

                        handled = true;
                    }

                    break;
                
                case State.WaitingForNumberOfVertices:
                    if (pending_fifo_data.get_size() >= 2) {
                        u16 data = read_from_pending_fifo_data!u16;
                        number_of_expected_vertices = data;
                        number_of_expected_bytes_for_shape = size_of_incoming_vertex(current_vat) * number_of_expected_vertices;
                        state = State.WaitingForVertexData;
                        log_hollywood("vat: %s", vats[current_vat]);
                        log_hollywood("vcd: %s", vertex_descriptors[current_vat]);
                        log_hollywood("Number of vertices: %d", number_of_expected_vertices);
                        log_hollywood("Number of expected bytes for shape: %d", number_of_expected_bytes_for_shape);
                        handled = true;
                    }

                    break;
                
                case State.WaitingForVertexData:
                    log_hollywood("%d += %d", number_of_received_bytes_for_shape, T.sizeof);
                    number_of_received_bytes_for_shape += T.sizeof;

                    if (number_of_received_bytes_for_shape >= number_of_expected_bytes_for_shape) {
                        process_new_shape();
                        state = State.WaitingForCommand;
                        number_of_received_bytes_for_shape = 0;
                        handled = true;
                    } else if (number_of_received_bytes_for_shape > number_of_expected_bytes_for_shape) {
                        error_hollywood("Received too many bytes for shape");
                    }

                    break;
                
                case State.WaitingForDisplayListAddress:
                    if (pending_fifo_data.get_size() >= 4) {
                        u32 address = read_from_pending_fifo_data!u32;
                        log_hollywood("Display list address: %08x", address);
                        this.display_list_address = address;
                        state = State.WaitingForDisplayListSize;
                        handled = true;
                    } else {
                        error_hollywood("Unexpected GX FIFO write");
                    }

                    break;
                
                case State.WaitingForDisplayListSize:
                    if (pending_fifo_data.get_size() >= 4) {
                        u32 size = read_from_pending_fifo_data!u32;
                        log_hollywood("Display list size: %08x", size);
                        this.display_list_size = size;
                        state = State.WaitingForCommand;
                        process_display_list(this.display_list_address, this.display_list_size);
                        handled = true;
                    } else {
                        error_hollywood("Unexpected GX FIFO write");
                    }

                    break;
            }
        } while (pending_fifo_data.get_size() > 0 && handled);
    }

    private size_t next_expected_size() {
        final switch (state) {
            case State.WaitingForCommand:
                return 1;
            case State.WaitingForBPWrite:
                return 4;
            case State.WaitingForCPReg:
                return 1;
            case State.WaitingForCPData:
                return 4;
            case State.WaitingForTransformUnitDescriptor:
                return 4;
            case State.WaitingForTransformUnitData:
                return 4;
            case State.WaitingForNumberOfVertices:
                return 2;
            case State.WaitingForVertexData:
                return 1;
            case State.WaitingForDisplayListAddress:
                return 4;
            case State.WaitingForDisplayListSize:
                return 4;
        }
    }

    private void handle_new_command(T)(T value) {
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
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[current_vat]);

                state = State.WaitingForNumberOfVertices;
                break;
            
            case GXFifoCommand.DrawTriangleFan | 0: .. case GXFifoCommand.DrawTriangleFan | 7:
                current_draw_command = GXFifoCommand.DrawTriangleFan;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[current_vat]);

                state = State.WaitingForNumberOfVertices;
                break;
            
            case GXFifoCommand.DrawTriangleStrip | 0: .. case GXFifoCommand.DrawTriangleStrip | 7:
                current_draw_command = GXFifoCommand.DrawTriangleStrip;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[current_vat]);

                state = State.WaitingForNumberOfVertices;
                break;
            
            case GXFifoCommand.DrawLines | 0: .. case GXFifoCommand.DrawLines | 7:
                current_draw_command = GXFifoCommand.DrawLines;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[current_vat]);

                state = State.WaitingForNumberOfVertices;
                break;
            
            case GXFifoCommand.DisplayList:
                state = State.WaitingForDisplayListAddress;
                break;
        
            default:
                error_hollywood("Unknown GX command: %02x", command);
                break;
        }
    }

    private void process_display_list(u32 address, u32 size) {
        address &= 0x01FF_FFFF;

        for (int i = 0; i < size; i++) {
            auto value = mem.paddr_read_u8(address + i * 1);
            log_hollywood("Display list: %08x %08x", address + i * 1, value);
        }

        log_hollywood("Display list: %08x %08x", address, size);

        while (size > 0) {
            size_t idx;
            size_t size_to_read = next_expected_size();

            log_hollywood("expected size to read: %d. address: %x", size_to_read, address);

            if (size_to_read > size) {
                error_hollywood("Display list too small");
            }

            u32 value;
            for (int i = 0; i < size_to_read; i++) {
                value <<= 8;
                value |= mem.paddr_read_u8(address + i);
            }

            switch (size_to_read) {
                case 1: process_fifo_write!(u8)(cast(u8) value, 0); break;
                case 2: process_fifo_write!(u16)(cast(u16) value, 0); break;
                case 4: process_fifo_write!(u32)(value, 0); break;
                default: error_hollywood("Invalid size to read: %d", size_to_read);
            }

            address += size_to_read;
            size -= size_to_read;
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
                if (bp_data << 5 == 0x01a4db90) {
                    error_hollywood("dumb fuck address");
                }
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
                int idx = (bp_register - 0x28);
                tev_config.stages[idx * 2 + 0].texmap        = bp_data.bits(0, 2);
                tev_config.stages[idx * 2 + 0].texcoord      = bp_data.bits(3, 5);
                tev_config.stages[idx * 2 + 0].texmap_enable = bp_data.bit(6);
                tev_config.stages[idx * 2 + 1].texmap        = bp_data.bits(12, 14);
                tev_config.stages[idx * 2 + 1].texcoord      = bp_data.bits(15, 17);
                tev_config.stages[idx * 2 + 1].texmap_enable = bp_data.bit(18);
                log_hollywood("texmaps: %d %d %d", idx, tev_config.stages[idx * 2 + 0].texmap, tev_config.stages[idx * 2 + 1].texmap);

                enabled_textures &= ~(3 << (idx * 2));
                enabled_textures |= (bp_data.bit(6)) << (idx * 2);
                enabled_textures |= (bp_data.bit(18)) << (idx * 2 + 1);

                ras_color[bp_register - 0x28] = cast(RasChannelId) bp_data.bits(19, 21);
                break;
            
            case 0xc0: .. case 0xdf:
                if (bp_register.bit(0)) {
                    log_hollywood("TEV_ALPHA_ENV_%x: %08x (tev op 1) at pc 0x%08x", bp_register - 0xc1, bp_data, mem.cpu.state.pc);
                    int idx = (bp_register - 0xc1) / 2;
                    tev_config.stages[idx].in_alfa_a = bp_data.bits(13, 15);
                    tev_config.stages[idx].in_alfa_b = bp_data.bits(10, 12);
                    tev_config.stages[idx].in_alfa_c = bp_data.bits(7, 9);
                    tev_config.stages[idx].in_alfa_d = bp_data.bits(4, 6);
                    tev_config.stages[idx].bias_alfa = 
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5;
                    tev_config.stages[idx].alfa_dest = bp_data.bits(22, 23);

                    if (bp_data.bits(16, 17) == 3) {
                        error_hollywood("Invalid bias");
                    }

                    tev_config.stages[idx].scale_alfa = 
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5;
                    
                    if (bp_data.bits(18, 19) > 3) {
                        error_hollywood("Invalid scale");
                    }

                    log_hollywood("Set indices to %d %d", bp_data.bits(0, 1), bp_data.bits(2, 3));
                    tev_config.stages[idx].ras_swap_table_index = value.bits(0, 1);
                    tev_config.stages[idx].tex_swap_table_index = value.bits(2, 3);
                    break;
                } else {
                    log_hollywood("%d TEV_COLOR_ENV_%x: %08x (tev op 0) at pc 0x%08x", shape_groups.length, bp_register - 0xc0, bp_data, mem.cpu.state.pc);
                    int idx = (bp_register - 0xc0) / 2;
                    tev_config.stages[idx].in_color_a = bp_data.bits(12, 15);
                    tev_config.stages[idx].in_color_b = bp_data.bits(8, 11);
                    tev_config.stages[idx].in_color_c = bp_data.bits(4, 7);
                    tev_config.stages[idx].in_color_d = bp_data.bits(0, 3);
                    tev_config.stages[idx].bias_color = 
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5;
                    tev_config.stages[idx].color_dest = bp_data.bits(22, 23);

                    if (bp_data.bits(16, 17) == 3) {
                        error_hollywood("Invalid bias");
                    }

                    tev_config.stages[idx].scale_color = 
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5;
                }
                break;
            
            case 0xe0: .. case 0xe7:
                // if (shape_groups.length == 15) {
                    log_hollywood("%d TEV_COLOR_REG_%x: %08x", shape_groups.length, bp_register - 0xe0, bp_data);
                // }
                if (bp_data.bit(23)) {
                    // set konst
                    // not yet i dont care
                } else {
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

            case 0x80: .. case 0x83:
                texture_descriptors[bp_register - 0x80].wrap_s = cast(TextureWrap) bp_data.bits(0, 1);
                texture_descriptors[bp_register - 0x80].wrap_t = cast(TextureWrap) bp_data.bits(2, 3);
                break;

            case 0xa0: .. case 0xa3:
                texture_descriptors[bp_register - 0xa0 + 4].wrap_s = cast(TextureWrap) bp_data.bits(0, 1);
                texture_descriptors[bp_register - 0xa0 + 4].wrap_t = cast(TextureWrap) bp_data.bits(2, 3);
                break;
            
            case 0x45:
                log_hollywood("PE interrupt: %08x", bp_data);
                scheduler.add_event_relative_to_clock(() { pixel_engine.raise_finish_interrupt(); }, 100_000);
                break;

            case 0x47:
                log_hollywood("tokenize interrupt: %08x", bp_data);
                scheduler.add_event_relative_to_clock(() { pixel_engine.raise_token_interrupt(cast(u16) bp_data.bits(0, 15)); }, 100_000);
                break;
            
            case 0xf6:
            case 0xf8:
            case 0xfa:
            case 0xfc:
                log_hollywood("TEV_SWAP_TABLE_%x: %08x", bp_register - 0xf6, value);
                int idx = (bp_register - 0xf6) / 2;
                tev_config.swap_tables &= ~(0xf << (idx * 8));
                tev_config.swap_tables |= value.bits(0, 3) << (idx * 8);
                break;
            
            case 0xf7:
            case 0xf9:
            case 0xfb:
            case 0xfd:
                int idx = (bp_register - 0xf6) / 2;
                tev_config.swap_tables &= ~(0xf << (idx * 8 + 4));
                tev_config.swap_tables |= value.bits(0, 3) << (idx * 8 + 4);
                break;

            default:
                log_hollywood("Unimplemented: BP register %02x", bp_register);
                break;
        }
    }

    void handle_new_cp_write(u8 register, u32 value) {
        switch (register) {
            case 0x50: .. case 0x57:
                log_hollywood("Setting vertex descriptor %d: %08x", register - 0x50, value);
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
                log_hollywood("asdf Setting vertex descriptor %d: %s", register - 0x50, *vcd);

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
                log_hollywood("asdf Setting vertex descriptor %d: %s", register - 0x60, *vcd);
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
                log_hollywood("asdf vat %d: %s", register - 0x70, *vat);

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
                log_hollywood("asdf vat %d: %s", register - 0x80, *vat);          

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
                log_hollywood("asdf vat %d: %s", register - 0x90, *vat);          
          
                break;
            
            case 0xa0: .. case 0xaf:
                log_hollywood("array_base: %02x %08x", register, value);
                array_bases[register - 0xa0] = value;
                break;

            case 0xb0: .. case 0xbf:
                array_strides[register - 0xb0] = value;
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

        final switch (vcd.position_location) {
            case VertexAttributeLocation.Direct:
                size += vat.position_count * calculate_expected_size_of_coord(vat.position_format);
                break;
            case VertexAttributeLocation.Indexed8Bit:  
                size += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit: 
                size += 2;
                break;
            case VertexAttributeLocation.NotPresent: break;
        }

        final switch (vcd.normal_location) {
            case VertexAttributeLocation.Direct:
                size += vat.normal_count * calculate_expected_size_of_normal(vat.normal_format);
                break;
            case VertexAttributeLocation.Indexed8Bit:
                size += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                size += 2;
                break;
            case VertexAttributeLocation.NotPresent: break;
        }

        final switch (vcd.position_normal_matrix_location) {
            case VertexAttributeLocation.Direct:
            case VertexAttributeLocation.Indexed8Bit:
            case VertexAttributeLocation.Indexed16Bit: error_hollywood("Matrix location not implemented"); break;
            case VertexAttributeLocation.NotPresent: break;
        }

        for (int i = 0; i < 8; i++) {
            final switch (vcd.texcoord_matrix_location[i]) {
                case VertexAttributeLocation.Direct:
                case VertexAttributeLocation.Indexed8Bit:
                case VertexAttributeLocation.Indexed16Bit: error_hollywood("Matrix location not implemented"); break;
                case VertexAttributeLocation.NotPresent: break;
            }
        }

        for (int i = 0; i < 2; i++) {
            final switch (vcd.color_location[i]) {
                case VertexAttributeLocation.Direct:
                    size += calculate_expected_size_of_color(vat.color_format[i]);
                    break;
                case VertexAttributeLocation.Indexed8Bit:
                    size += 1;
                    break;
                case VertexAttributeLocation.Indexed16Bit:
                    size += 2;
                    break;
                case VertexAttributeLocation.NotPresent: break;
            }
        }

        for (int i = 0; i < 8; i++) {
            final switch (vcd.texcoord_location[i]) {
                case VertexAttributeLocation.Direct:
                    size += vat.texcoord_count[i] * calculate_expected_size_of_coord(vat.texcoord_format[i]);
                    break;
                case VertexAttributeLocation.Indexed8Bit:
                    size += 1;
                    break;
                case VertexAttributeLocation.Indexed16Bit:
                    size += 2;
                    break;
                case VertexAttributeLocation.NotPresent: break;
            }
        }

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
                int idx = register - 0x1040;

                assert_hollywood(value.bits(7, 11) <= 12, "Invalid tex coord source");
                log_hollywood("texcoord_source[%d]: %d", idx, value.bits(7, 11));
                texture_descriptors[idx].texcoord_source = cast(TexcoordSource) value.bits(7, 11);
                break;

            case 0x0000: .. case 0x00ff:
                general_matrix_ram[register] = force_cast!float(value);
                break;
            
            case 0x0500: .. case 0x05ff:
                dt_texture_matrix_ram[register - 0x500] = force_cast!float(value);
                break;
            
            case 0x1050: .. case 0x1057:
                int idx = register - 0x1050;

                texture_descriptors[idx].dualtex_matrix_slot = value.bits(0, 5);
                texture_descriptors[idx].normalize_before_dualtex = value.bit(7);
                break;
            
            case 0x100c:
                color_global[0] = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                break;
            
            case 0x100d:
                color_global[1] = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                break;
            
            case 0x100e:
                this.color_configs[0].material_src = cast(MaterialSource) value.bit(0);
                break;
            
            case 0x100f:
                this.color_configs[1].material_src = cast(MaterialSource) value.bit(0);
                break;
            
            case 0x103f:
                // num texgens, who cares
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
                return (cast(float) cast(u8) value) / (cast(float) (1 << shift));
            
            case CoordFormat.S8:
                return (cast(float) (sext_32((cast(s8) value), 8))) / (cast(float) (1 << shift));
            
            case CoordFormat.U16:
                return (cast(float) (cast(u16) value)) / (cast(float) (1 << shift));
            
            case CoordFormat.S16:
                return (cast(float) (sext_32((cast(s16) value), 16))) / (cast(float) (1 << shift));
            
            case CoordFormat.F32:
                if (shift != 0) {
                    error_hollywood("Unexpected shift for F32 format: %d", shift);
                }
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
                    (cast(float) (value.bits(12, 15) << 4)) / 0xff,
                ];
            
            case ColorFormat.RGBA6666:
                return [
                    (cast(float) (value.bits(0, 5) << 2)) / 0xff,
                    (cast(float) (value.bits(6, 11) << 2)) / 0xff,
                    (cast(float) (value.bits(12, 17) << 2)) / 0xff,
                    (cast(float) (value.bits(18, 23) << 2)) / 0xff,
                ];
            
            case ColorFormat.RGBA8888:
                return [
                    (cast(float) (value.bits(24, 31))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(0, 7))) / 0xff,
                ];
        }
    }

    private size_t calculate_expected_size_of_coord(CoordFormat format) {
        final switch (format) {
            case CoordFormat.U8:  return 1;
            case CoordFormat.S8:  return 1;
            case CoordFormat.U16: return 2;
            case CoordFormat.S16: return 2;
            case CoordFormat.F32: return 4;
        }
    }

    private size_t calculate_expected_size_of_color(ColorFormat format) {
        final switch (format) {
            case ColorFormat.RGB565:   return 2;
            case ColorFormat.RGB888:   return 3;
            case ColorFormat.RGB888x:  return 4;
            case ColorFormat.RGBA4444: return 2;
            case ColorFormat.RGBA6666: return 3;
            case ColorFormat.RGBA8888: return 4;
        }
    }

    private size_t calculate_expected_size_of_normal(NormalFormat format) {
        final switch (format) {
            case NormalFormat.S8:  return 1;
            case NormalFormat.S16: return 2;
            case NormalFormat.F32: return 4;
        }
    }

    private u32 get_vertex_attribute(VertexAttributeLocation location, size_t offset, size_t size, int arr_idx) {
        u32 data = 0;

        switch (location) {
            case VertexAttributeLocation.Indexed8Bit:
                // data = read_from_indexed_array(arr_idx, read_from_shape_data_buffer(offset, 1), size);
                break;
            case VertexAttributeLocation.Indexed16Bit:
                // data = read_from_indexed_array(arr_idx, read_from_shape_data_buffer(offset, 2), size);
                break;
            case VertexAttributeLocation.Direct:
                data = read_from_shape_data_buffer(offset, size);
                break;
            default:
                error_hollywood("Unimplemented vertex attribute location");
        }

        return data;
    }

    private u32 read_from_shape_data_buffer(size_t offset, size_t size) {
        u32 data = 0;
        for (int i = 0; i < size; i++) {
            data <<= 8;
            data |= pending_fifo_data.remove();
        }

        log_hollywood("read_from_shape_data_buffer: %x", data);
        return data;
    }

    private u32 read_from_indexed_array(int array_num, int idx, int offset, size_t size) {
        u32 array_addr = array_bases[array_num];
        u32 array_stride = array_strides[array_num];
        u32 array_offset = array_addr + (array_stride * idx) + (offset * cast(int) size);

        final switch (size) {
        case 1: return mem.paddr_read_u8(array_offset);
        case 2: return mem.paddr_read_u16(array_offset);
        case 4: return mem.paddr_read_u32(array_offset);
        }
    }

    private size_t get_size_of_vertex_attribute_in_stream(VertexAttributeLocation location, size_t size_of_attribute) {
        switch (location) {
            case VertexAttributeLocation.Indexed8Bit:  return 1;
            case VertexAttributeLocation.Indexed16Bit: return 2;
            case VertexAttributeLocation.Direct:       return size_of_attribute;
            default:                                   return 0;
        }
    }

    private void process_new_shape() {
        log_hollywood("process_new_shape %d %s %s", shape_groups.length, vats[current_vat], vertex_descriptors[current_vat]);
        glUseProgram(gl_program);

        ShapeGroup shape_group;
        shape_group.shapes = PageAllocator!Shape(0);
        shape_group.textured = false;
        shape_group.position_matrix = general_matrix_ram[0 .. 12]; // ????
        shape_group.projection_matrix = projection_matrix;


        int enabled_textures_bitmap;
        for (int i = 0; i < 8; i++) {
            if (tev_config.stages[i].texmap_enable) { 
                int j = tev_config.stages[i].texmap;
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

                shape_group.texture[j].normalize_before_dualtex = texture_descriptors[j].normalize_before_dualtex;

                shape_group.textured = true;
                enabled_textures_bitmap |= 1 << j;
            }
        }

        int offset = 0;
        vertex_allocator.reset();
            auto vcd = &vertex_descriptors[current_vat];
            auto vat = &vats[current_vat];
        for (int i = 0; i < number_of_expected_vertices; i++) {
            Vertex* v = vertex_allocator.allocate();
            
            // auto vcd = &vertex_descriptors[current_vat];
            // auto vat = &vats[current_vat];

            if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
                error_hollywood("Matrix location not implemented");
            }

            for (int j = 0; j < 8; j++) {
                if (vcd.texcoord_matrix_location[j] != VertexAttributeLocation.NotPresent) {
                    error_hollywood("Matrix location not implemented");
                }
            }
            
            final switch (vcd.position_location) {
            case VertexAttributeLocation.Direct:
                for (int j = 0; j < vat.position_count; j++) {
                    v.position[j] = dequantize_coord(
                        read_from_shape_data_buffer(offset, calculate_expected_size_of_coord(vat.position_format)),
                        vat.position_format, vat.position_shift);
                    offset += calculate_expected_size_of_coord(vat.position_format);
                }
                break;
            case VertexAttributeLocation.Indexed8Bit:
                auto array_offset = read_from_shape_data_buffer(offset, 1);
                for (int j = 0; j < vat.position_count; j++) {
                    size_t size = calculate_expected_size_of_coord(vat.position_format);
                    log_hollywood("processing position with size %d", size);
                    u32 data = read_from_indexed_array(0, array_offset, j, size);
                    v.position[j] = dequantize_coord(data, vat.position_format, vat.position_shift);
                }
                offset += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                auto array_offset = read_from_shape_data_buffer(offset, 2);
                for (int j = 0; j < vat.position_count; j++) {
                    size_t size = calculate_expected_size_of_coord(vat.position_format);
                    log_hollywood("processing position with size %d", size);
                    u32 data = read_from_indexed_array(0, array_offset, j, size);
                    v.position[j] = dequantize_coord(data, vat.position_format, vat.position_shift);
                }
                offset += 2;
                break;
            case VertexAttributeLocation.NotPresent:
                break;
                // error_hollywood("Position location not present");
            }

            if (vat.position_count == 2) {
                v.position[2] = 0.0; // z coordinate is always 0 for 2D shapes
            }            

            final switch (vcd.normal_location) {
            case VertexAttributeLocation.Direct:
                size_t size = calculate_expected_size_of_normal(vat.normal_format);
                for (int j = 0; j < vat.normal_count; j++) {
                    read_from_shape_data_buffer(offset, size);
                    offset += size;
                }
                break;
            case VertexAttributeLocation.Indexed8Bit:
                read_from_shape_data_buffer(offset, 1);
                offset += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                read_from_shape_data_buffer(offset, 2);
                offset += 2;
                break;
            case VertexAttributeLocation.NotPresent:
                break;
            }

            for (int j = 0; j < 2; j++) {
                float[4] color;

                final switch (vcd.color_location[j]) {
                case VertexAttributeLocation.Direct:
                    size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                    log_hollywood("processing color with size %d", size);
                    u32 color_data = get_vertex_attribute(vcd.color_location[j], offset, size, j + 2);
                    color = dequantize_color(color_data, vat.color_format[j], j);

                    if (vat.color_count[j] == 3) {
                        color[3] = 1.0;
                    }

                    offset += get_size_of_vertex_attribute_in_stream(vcd.color_location[j], size);
                    break;
                
                case VertexAttributeLocation.Indexed8Bit:
                    read_from_shape_data_buffer(offset, 1);
                    offset += 1;
                    break;
                
                case VertexAttributeLocation.Indexed16Bit:  
                    read_from_shape_data_buffer(offset, 2);
                    offset += 2;
                    break;
                case VertexAttributeLocation.NotPresent:
                    break;
                }

                final switch (this.color_configs[j].material_src) {
                    case MaterialSource.FromGlobal:
                        v.color[j] = color_global[j];
                        break;
                    case MaterialSource.FromVertex:
                        v.color[j] = color;
                        break;
                }
            }

            // for (int j = 0; j < 8; j++) {
            for (int j = 0; j < 8; j++) { 
                final switch (vcd.texcoord_location[j]) {
                case VertexAttributeLocation.Direct:
                    log_hollywood("processing texcoord with size %d", vat.texcoord_count[j]);
                    for (int k = 0; k < vat.texcoord_count[j]; k++) {
                        size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                        u32 texcoord = get_vertex_attribute(vcd.texcoord_location[j], offset, size, j + 4);
                        v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                        offset += get_size_of_vertex_attribute_in_stream(vcd.texcoord_location[j], size);
                    }
                    break;
                case VertexAttributeLocation.Indexed8Bit:
                    auto array_offset = read_from_shape_data_buffer(offset, 1);
                    log_hollywood("processing texcoord with size %d", vat.texcoord_count[j]);
                    for (int k = 0; k < vat.texcoord_count[j]; k++) {
                        size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                        u32 texcoord = read_from_indexed_array(j + 4, array_offset, k, size);
                        v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                    }
                    offset += 1;
                    break;
                case VertexAttributeLocation.Indexed16Bit:
                    auto array_offset = read_from_shape_data_buffer(offset, 2);
                    log_hollywood("processing texcoord with size %d", vat.texcoord_count[j]);
                    for (int k = 0; k < vat.texcoord_count[j]; k++) {
                        size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                        u32 texcoord = read_from_indexed_array(j + 4, array_offset, k, size);
                        v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                    }
                    offset += 2;
                    break;
                case VertexAttributeLocation.NotPresent:
                    break;
                }
            }

        }

        for (int i = 0; i < 8; i++) {
            shape_group.vertex_config.tex_configs[i].tex_matrix = shape_group.texture[i].tex_matrix;
            shape_group.vertex_config.tex_configs[i].dualtex_matrix = shape_group.texture[i].dualtex_matrix; 
            shape_group.vertex_config.tex_configs[i].normalize_before_dualtex = shape_group.texture[i].normalize_before_dualtex;
            shape_group.vertex_config.tex_configs[i].texcoord_source = cast(u32) texture_descriptors[i].texcoord_source;
        }

        shape_group.enabled_textures_bitmap = enabled_textures_bitmap;

        shape_group.tev_config = tev_config;

        for (int i = 0; i < 16; i++) {
            // if (shape_groups.length == 132) {
            //     log_hollywood("ras_color[%d]: %s", i, ras_color[i]);
            // }
            // switch (ras_color[i]) {
            //     case RasChannelId.Color0: 
            //         shape_group.tev_config.ras[i][0] = shape_group.color[0][0];
            //         shape_group.tev_config.ras[i][1] = shape_group.color[0][1];
            //         shape_group.tev_config.ras[i][2] = shape_group.color[0][2];
            //         shape_group.tev_config.ras[i][3] = shape_group.color[0][3];
            //         break;
            //     case RasChannelId.Color1:
            //         shape_group.tev_config.ras[i][0] = shape_group.color[1][0];
            //         shape_group.tev_config.ras[i][1] = shape_group.color[1][1];
            //         shape_group.tev_config.ras[i][2] = shape_group.color[1][2];
            //         shape_group.tev_config.ras[i][3] = shape_group.color[1][3];
            //         break;
            //     default: log_hollywood("unimpelmented ras: %x", ras_color[i]); break;
            // }
            if (ras_color[i] != 0 && ras_color[i] != 0x1 && ras_color[i] != 0x7) {
                error_hollywood("Unimplemented ras color: %x", ras_color[i]);
            }
            tev_config.stages[i].ras_channel_id = cast(RasChannelId) ras_color[i];
        }

        // shape_group.tev_config.konst_a[0] = 1.0f;
        // shape_group.tev_config.konst_a[1] = 1.0f;
        // shape_group.tev_config.konst_a[2] = 0.0f;
        // shape_group.tev_config.konst_a[3] = 1.0f;

        switch (current_draw_command) {
            case GXFifoCommand.DrawQuads:
                log_hollywood("DrawQuads(%d)", vertex_allocator.length);
                for (int i = 0; i < vertex_allocator.length; i += 4) {
                    Shape* shape = shape_group.shapes.allocate();
                    shape.vertices = [vertex_allocator[i], vertex_allocator[i + 1], vertex_allocator[i + 2]];
                }

                for (int i = 0; i < vertex_allocator.length; i += 4) {
                    Shape* shape = shape_group.shapes.allocate();
                    shape.vertices = [vertex_allocator[i + 0], vertex_allocator[i + 2], vertex_allocator[i + 3]];
                }
                break;
            
            case GXFifoCommand.DrawTriangleFan:
                for (int i = 1; i < vertex_allocator.length - 2; i++) {
                    Shape* shape = shape_group.shapes.allocate();
                    shape.vertices = [vertex_allocator[0], vertex_allocator[i + 1], vertex_allocator[i + 2]];
                }
                break;
            
            case GXFifoCommand.DrawTriangleStrip:
                for (int i = 0; i < vertex_allocator.length - 2; i++) {
                    Shape* shape = shape_group.shapes.allocate();
                    shape.vertices = [vertex_allocator[i], vertex_allocator[i + 1], vertex_allocator[i + 2]];
                }
                break;
            
            case GXFifoCommand.DrawLines:
                // i dont care
                break;
            
            default: error_hollywood("Unimplemented draw command: %s", current_draw_command);
        }
        
        ShapeGroup* slot = shape_groups.allocate();
        *slot = shape_group;
        if (shape_groups.length == 17) {
            log_hollywood("awni: %s", texture_descriptors[0]);
        }
    }

    bool shit = false;

    public void draw() {
        draw_shape_groups(shape_groups.all()[0 .. shape_groups.length]);
    }

    void draw_shape_groups(ShapeGroup[] shape_groups) {
        if (shape_groups.length == 0) {
            return;
        }

        glUseProgram(gl_program);
        glClearColor(0, 0, 0, 1); 
        // glClearDepth(1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        // glEnable(GL_DEPTH_TEST);
        // glDepthFunc(GL_ALWAYS);
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
            if (mem.mmio.ipc.file_manager.usb_dev_57e305.usb_manager.bluetooth.wiimote.button_state & 4) {
                log_hollywood("New Shapegroup: %s", shape_group);
            }
            if (i == 16) {
                log_hollywood("New Shapegroup: %s", shape_group);
            }
            i++;
            draw_shape_group(shape_group, texnum);
            debug_drawn_shape_groups ~= shape_group;
        }

        this.shape_groups.reset();
    }

    void draw_shape_group(ShapeGroup shape_group, int texnum) {
        if (shape_group.textured) {
            int enabled_textures_bitmap = shape_group.enabled_textures_bitmap;
            while (enabled_textures_bitmap != 0) {
                int i = cast(int) enabled_textures_bitmap.bfs;
                enabled_textures_bitmap &= ~(1 << i);

                GLuint texture_id = gl_object_manager.allocate_texture_object();

                // "Bind" the newly created texture : all future texture functions will modify this texture
                glActiveTexture(GL_TEXTURE0 + i);
                glBindTexture(GL_TEXTURE_2D, texture_id);
                glActiveTexture(GL_TEXTURE0 + i);

                // Give the image to OpenGL
                // log_hollywood("projection color: %s", shape.texture[0]);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, cast(GLint) shape_group.texture[i].height, cast(GLint) shape_group.texture[i].width, 0, GL_BGRA, GL_UNSIGNED_BYTE, shape_group.texture[i].data);

                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

                final switch (shape_group.texture[i].wrap_s) {
                    case TextureWrap.Clamp:
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                        break;
                    
                    case TextureWrap.Repeat:
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
                        break;
                    
                    case TextureWrap.Mirror:
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_MIRRORED_REPEAT);
                        break;
                }

                final switch (shape_group.texture[i].wrap_t) {
                    case TextureWrap.Clamp:
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                        break;
                    
                    case TextureWrap.Repeat:
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
                        break;
                    
                    case TextureWrap.Mirror:
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_MIRRORED_REPEAT);
                        break;
                }

                glUniform1i(texture_uniform_locations[i], i);
            }

            
            texnum++;
        } else {
            return;
        }
    
        submit_shape_group_to_opengl(shape_group);
    }

    void submit_shape_group_to_opengl(ShapeGroup shape_group) {
        log_hollywood("swap_tables: %x %x", shape_group.tev_config.swap_tables, shape_group.tev_config.stages[0].ras_swap_table_index);
        log_hollywood("Submitting shape group to OpenGL (%d): %s", shape_group.shapes.length, shape_group);
        // log_hollywood("pointer data: %x %x %x", shape_group.shapes.ptr, shape_group.shapes[0].vertices.ptr, shape_group.shapes[0].vertices[2].position.ptr);

        uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
        uint vertex_buffer_object = gl_object_manager.allocate_vertex_buffer_object();
        glBindVertexArray(vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object);
        glBufferData(GL_ARRAY_BUFFER, 30 * shape_group.shapes.length * GLfloat.sizeof * 3, shape_group.shapes.all(), GL_STATIC_DRAW);

        auto position_location = glGetAttribLocation(gl_program, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, 30 * float.sizeof, cast(void*) 0);

        auto normal_location = glGetAttribLocation(gl_program, "normal");
        glEnableVertexAttribArray(normal_location);
        glVertexAttribPointer(normal_location, 3, GL_FLOAT, GL_FALSE, 30 * float.sizeof, cast(void*) (3 * float.sizeof));

        auto texcoord_location = glGetAttribLocation(gl_program, "texcoord");
        glEnableVertexAttribArray(texcoord_location);
        glVertexAttribPointer(texcoord_location, 2, GL_FLOAT, GL_FALSE, 30 * float.sizeof, cast(void*) (6 * float.sizeof));

        auto color_location = glGetAttribLocation(gl_program, "in_color");
        glEnableVertexAttribArray(color_location);
        glVertexAttribPointer(color_location, 4, GL_FLOAT, GL_FALSE, 30 * float.sizeof, cast(void*) (22 * float.sizeof));

        glUniformMatrix4x3fv(glGetUniformLocation(gl_program, "position_matrix"), 1, GL_TRUE,  shape_group.position_matrix.ptr);
        glUniformMatrix4x3fv(glGetUniformLocation(gl_program, "texture_matrix"),  1, GL_TRUE,  shape_group.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv  (glGetUniformLocation(gl_program, "MVP"),             1, GL_FALSE, shape_group.projection_matrix.ptr);

        uint tev_ubo = gl_object_manager.allocate_uniform_buffer_object();
        glBindBuffer(GL_UNIFORM_BUFFER, tev_ubo);
        log_hollywood("TevConfig: sizeof %d", TevConfig.sizeof);
        glBufferData(GL_UNIFORM_BUFFER, TevConfig.sizeof, &shape_group.tev_config, GL_STATIC_DRAW);
        glUniformBlockBinding(gl_program, glGetUniformBlockIndex(gl_program, "TevConfig"), 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, tev_ubo);

        uint vertex_ubo = gl_object_manager.allocate_uniform_buffer_object();
        glBindBuffer(GL_UNIFORM_BUFFER, vertex_ubo);
        glBufferData(GL_UNIFORM_BUFFER, VertexConfig.sizeof, &shape_group.vertex_config, GL_STATIC_DRAW);
        glUniformBlockBinding(gl_program, glGetUniformBlockIndex(gl_program, "VertexConfig"), 1);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, vertex_ubo);

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
            import core.stdc.stdlib;
            import std.string;
            
            char* info_log = cast(char*) malloc(10000000);
            int info_log_length;

            glGetShaderInfoLog(vertex_shader, 10000000, &info_log_length, cast(char*) info_log);
            error_hollywood("Vertex shader compilation error: %s", info_log.fromStringz);
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

        // cry about it
        texture_uniform_locations = [
            glGetUniformLocation(gl_program, "wiiscreen0"),
            glGetUniformLocation(gl_program, "wiiscreen1"),
            glGetUniformLocation(gl_program, "wiiscreen2"),
            glGetUniformLocation(gl_program, "wiiscreen3"),
            glGetUniformLocation(gl_program, "wiiscreen4"),
            glGetUniformLocation(gl_program, "wiiscreen5"),
            glGetUniformLocation(gl_program, "wiiscreen6"),
            glGetUniformLocation(gl_program, "wiiscreen7"),
        ];

        log_hollywood("uniform locations: %s", texture_uniform_locations);
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

    void debug_draw_texture(Texture texture, int x, int y, int w, int h) {
        GLuint texture_id = gl_object_manager.allocate_texture_object();

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture_id);
        glActiveTexture(GL_TEXTURE0);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, cast(GLint) texture.height, cast(GLint) texture.width, 0, GL_BGRA, GL_UNSIGNED_BYTE, texture.data);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

        glUniform1i(texture_uniform_locations[0], 0);

        auto xf = cast(float) x;
        auto yf = cast(float) y;
        auto wf = cast(float) w;
        auto hf = cast(float) h;

        log_frontend("x from %f to %f, y from %f to %f, w %f, h %f", xf, xf + wf, yf, yf + hf, wf, hf);

        float display_ratio = wf / hf;
        float texture_ratio = cast(float) texture.width / cast(float) texture.height;
        if (display_ratio > texture_ratio) {
            // display is wider than texture
            wf = cast(float) texture.width * (hf / cast(float) texture.height);
        } else if (display_ratio < texture_ratio) {
            // display is taller than texture
            auto new_hf = cast(float) texture.height * (wf / cast(float) texture.width);
            yf += (hf - new_hf);
            hf = new_hf;
        }

        // im so goddamn fucking sorry
        import ui.sdl.device;
        int screen_width  = DebugTriWindow.DEBUG_TRI_WINDOW_WIDTH;
        int screen_height = DebugTriWindow.DEBUG_TRI_WINDOW_HEIGHT;

        float[20] vertices = [
            xf / screen_width * 2 - 1, yf / screen_height * 2 - 1, 0.0,
            1.0, 0.0,
            xf / screen_width * 2 - 1, (yf + hf) / screen_height * 2 - 1, 0.0,
            0.0, 0.0,
            (xf + wf) / screen_width * 2 - 1, (yf + hf) / screen_height * 2 - 1, 0.0,
            0.0, 1.0,
            (xf + wf) / screen_width * 2 - 1, yf / screen_height * 2 - 1, 0.0,
            1.0, 1.0,
        ];

        uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
        uint vertex_buffer_object = gl_object_manager.allocate_vertex_buffer_object();

        glBindVertexArray(vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object);

        auto position_location = glGetAttribLocation(gl_program, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, float.sizeof * 5, cast(void*) 0);

        auto uv_location = glGetAttribLocation(gl_program, "texcoord");
        glEnableVertexAttribArray(uv_location);
        glVertexAttribPointer(uv_location, 2, GL_FLOAT, GL_FALSE, float.sizeof * 5, cast(void*) (float.sizeof * 3));

        log_frontend("locations: %d %d", position_location, uv_location);
        glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof, cast(void*) vertices.ptr, GL_STATIC_DRAW);
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
    }

    void debug_reload_shaders() {
        load_shaders();
    }

    void on_error() {
        import std.stdio;
        
        foreach (debug_value; fifo_debug_history.get()) {
            writefln("FIFO_DEBUG: (%016x %s)", debug_value.value, debug_value.state);
        }
    }
}