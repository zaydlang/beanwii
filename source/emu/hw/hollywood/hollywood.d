module emu.hw.hollywood.hollywood;

import bindbc.opengl;
import emu.hw.cp.cp;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.gxfifo_ringbuffer;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.hollywood_types : Vertex, Texture, RenderState, ShapeGroup, Shape, TevConfig, VertexConfig, VertexDescriptor, VertexAttributeTable, VertexAttributeLocation, ProjectionMode, CoordFormat, NormalFormat, ColorFormat, MaterialSource, ColorConfig, RasChannelId, State;
import emu.hw.hollywood.opengl_renderer;
import emu.hw.hollywood.texture;
import emu.hw.pe.pe;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import std.file;
import std.stdio;
import util.bitop;
import util.force_cast;
import util.log;
import util.number;
import util.page_allocator;
import util.ringbuffer;


final class Hollywood {
    VertexAttributeTable[8] vats;
    ColorConfig[2] color_configs;

    int next_bp_mask = 0x00ff_ffff;
    u32[256] bp_registers;

    ProjectionMode projection_mode;

    VertexDescriptor[8] vertex_descriptors;

    private State state;
    private size_t cached_bytes_needed = 1;
    
    private u32 xfb_addr;
    private u32 xfb_stride;
    private u8 tex_copy_format;
    private u8 cp_register;

    private u16 xf_register;
    private u16 xf_data_remaining;

    private GXFifoCommand current_draw_command;
    private int current_vat;
    private int number_of_expected_vertices;
    private int number_of_expected_bytes_for_shape;
    private int number_of_received_bytes_for_shape;
    
    private int bazinga;

    private GLfloat[6]  projection_matrix_parameters;
    private float[256] general_matrix_ram;
    private float[256] dt_texture_matrix_ram;

    private u32[4] load_mtx_idx_values;
    private int current_load_mtx_idx;

    private float[4][2] color_global;

    private GlObjectManager gl_object_manager;
    private TextureManager texture_manager;
    
    private bool xfb_has_data = false;
    
    private u8[640 * 528 * 4] rgba_buffer;
    private u8[640 * 528 * 4] converted_buffer;
    
    private float[6] viewport;
    
    private u32 display_list_address;
    private u32 display_list_size;
    
    private OpenGLRenderer opengl_renderer;
    private ShapeGroup accumulated_geometry;

    u32[16] array_bases;
    u32[16] array_strides;

    GLint uniform_buffer_alignment;
    
    auto next_vertex() {
        return opengl_renderer.allocate_vertex();
    }

    auto next_index() {
        return opengl_renderer.allocate_index();
    }

    struct FifoDebugValue {
        u64 value;
        State state;
    }

    RingBuffer!FifoDebugValue fifo_debug_history;
    GXFifoRingBuffer pending_fifo_data;

    this() {
        pending_fifo_data = new GXFifoRingBuffer(256);
        fifo_debug_history = new RingBuffer!FifoDebugValue(100);
    }

    void init_opengl() {
        gl_object_manager = new GlObjectManager();
        texture_manager = new TextureManager();
        state = State.WaitingForCommand;

        opengl_renderer = new OpenGLRenderer(gl_object_manager);
        opengl_renderer.init_opengl();
    }

    private void flush_accumulated_batch() {
        if (accumulated_geometry.shared_index_count == 0) {
            return;
        }
        
        if (opengl_renderer.get_render_state().uses_per_vertex_matrices) {
            opengl_renderer.set_general_matrix_ram(general_matrix_ram);
        }

        opengl_renderer.flush_and_render(accumulated_geometry);

        accumulated_geometry.shared_index_count = 0;
        accumulated_geometry = ShapeGroup();
    }

    private auto get_render_state_for_modification() {
        if (accumulated_geometry.shared_index_count > 0) {
            flush_accumulated_batch();
        }
        
        return opengl_renderer.get_render_state_for_modification();
    }
    
    public auto get_current_render_state() const {
        return opengl_renderer.get_render_state();
    }

    private void submit_shape_group(ShapeGroup geometry) {
        if (accumulated_geometry.shared_index_count == 0) {
            accumulated_geometry = geometry;
        } else {
            accumulated_geometry.shared_index_count += geometry.shared_index_count;
        }
    }

    public const(RenderState)* get_current_render_state() const {
        return &current_render_state;
    }
    
    private void flush_if_needed() {
        if (accumulated_geometry.shared_index_count > 0) {
            flush_accumulated_batch();
        }
    }

    private void apply_opengl_state(RenderState render_state) {
        glUseProgram(gl_program);
        glClearColor(
            blitting_processor.get_copy_clear_color_red() / 255.0f,
            blitting_processor.get_copy_clear_color_green() / 255.0f, 
            blitting_processor.get_copy_clear_color_blue() / 255.0f,
            blitting_processor.get_copy_clear_color_alpha() / 255.0f
        ); 
        
        gl_object_manager.deallocate_all_objects();

        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE, render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv(mvp_uniform_location, 1, GL_FALSE, render_state.projection_matrix.ptr);

        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, TevConfig.sizeof, &render_state.tev_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_tev_buffer);

        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, VertexConfig.sizeof, &render_state.vertex_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_vertex_config_buffer);

        if (render_state.arithmetic_blending_enable) {
            glEnable(GL_BLEND);

            auto op1 = gc_blend_factor_to_gl(render_state.blend_source);
            auto op2 = gc_blend_factor_to_gl(render_state.blend_destination);
            glBlendFunc(op1, op2);
        } else {
            glDisable(GL_BLEND);
        }

        while (render_state.enabled_textures_bitmap != 0) {
            int i = cast(int) render_state.enabled_textures_bitmap.bfs;
            render_state.enabled_textures_bitmap &= ~(1 << i);

            glActiveTexture(GL_TEXTURE0 + i);
            glBindTexture(GL_TEXTURE_2D, render_state.texture[i].texture_id);

            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

            final switch (render_state.texture[i].wrap_s) {
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

            final switch (render_state.texture[i].wrap_t) {
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

        glColorMask(
            render_state.color_update_enable, 
            render_state.color_update_enable, 
            render_state.color_update_enable, 
            render_state.alpha_update_enable
        );

        if (render_state.depth_test_enabled) {
            glEnable(GL_DEPTH_TEST);
            glDepthFunc(render_state.depth_func);
        } else {
            glDisable(GL_DEPTH_TEST);
        }

        glDepthMask(render_state.depth_write_enabled ? GL_TRUE : GL_FALSE);

        final switch (render_state.cull_mode) {
            case 0:
                // glDisable(GL_CULL_FACE);
                break;
            case 1:
                // glEnable(GL_CULL_FACE);
                // glCullFace(GL_FRONT);
                break;
            case 2:
                // glEnable(GL_CULL_FACE);
                // glCullFace(GL_BACK);
                break;
            case 3:
                // glEnable(GL_CULL_FACE);
                // glCullFace(GL_FRONT_AND_BACK);
                break;
        }
    }
    
    void execute_efb_copy(u32 control_register, bool clear_efb) {
        flush_accumulated_batch();

        bool is_display_copy = control_register.bit(14);
        if (is_display_copy) {
            opengl_renderer.efb_copy_to_xfb();
        } else {
            execute_efb_to_texture_copy(control_register.bit(9));
        }
        
        if (clear_efb) {
            opengl_renderer.clear_efb();
        }
    }
    
    void execute_efb_to_texture_copy(bool mipmap) {
        auto render_state = get_render_state_for_modification();
        u16 src_x = render_state.efb_src_x;
        u16 src_y = render_state.efb_src_y;
        u16 width = render_state.efb_src_w;
        u16 height = render_state.efb_src_h;
        u32 dest_addr = xfb_addr;
        
        opengl_renderer.efb_copy_to_texture(rgba_buffer.ptr);
        
        if (mipmap) {
            downsample_rgba_buffer_by_2(rgba_buffer.ptr, width, height);
            width /= 2;
            height /= 2;
        }
        
        u8 dest_format = tex_copy_format;
        
        switch (dest_format) {
            case 0x6:
                write_rgba32_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            case 0x4:
                write_rgb565_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            case 0x5: 
                write_rgb5a3_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            case 0x1:
                write_i8_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            case 0x7:
                write_a8_as_i8_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            case 0x8:
                write_r8_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            case 0xB:
                write_rg8_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
            default:
                error_hollywood("Unsupported texture copy destination format: 0x%x", dest_format);
                return;
        }

        log_hollywood("EFB to texture copy: src=(%d,%d), size=(%d,%d), dest=0x%08X, dest_format=0x%x",
                        src_x, src_y, width, height, dest_addr, dest_format);
        
        texture_manager.invalidate_texture_at_address(dest_addr);
    }
    
    void downsample_rgba_buffer_by_2(u8* buffer, u16 width, u16 height) {
        u16 new_width = width / 2;
        u16 new_height = height / 2;
        
        for (int y = 0; y < new_height; y++) {
            for (int x = 0; x < new_width; x++) {
                int src_x = x * 2;
                int src_y = y * 2;
                
                int src_offset1 = (src_y * width + src_x) * 4;
                int src_offset2 = (src_y * width + src_x + 1) * 4;
                int src_offset3 = ((src_y + 1) * width + src_x) * 4;
                int src_offset4 = ((src_y + 1) * width + src_x + 1) * 4;
                
                int dst_offset = (y * new_width + x) * 4;
                
                buffer[dst_offset + 0] = cast(u8) ((buffer[src_offset1 + 0] + buffer[src_offset2 + 0] + buffer[src_offset3 + 0] + buffer[src_offset4 + 0]) / 4);
                buffer[dst_offset + 1] = cast(u8) ((buffer[src_offset1 + 1] + buffer[src_offset2 + 1] + buffer[src_offset3 + 1] + buffer[src_offset4 + 1]) / 4);
                buffer[dst_offset + 2] = cast(u8) ((buffer[src_offset1 + 2] + buffer[src_offset2 + 2] + buffer[src_offset3 + 2] + buffer[src_offset4 + 2]) / 4);
                buffer[dst_offset + 3] = cast(u8) ((buffer[src_offset1 + 3] + buffer[src_offset2 + 3] + buffer[src_offset3 + 3] + buffer[src_offset4 + 3]) / 4);
            }
        }
    }
    
    void write_i8_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 8);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 8; fine_x++) {
                int x = tile_x * 8 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    // Convert RGB to luminance using standard weights
                    u8 r = src[src_offset + 0];
                    u8 g = src[src_offset + 1];
                    u8 b = src[src_offset + 2];
                    u8 luminance = cast(u8) ((r * 299 + g * 587 + b * 114) / 1000);
                    
                    mem.physical_write_u8(current_address, luminance);
                } else {
                    mem.physical_write_u8(current_address, 0);
                }
                current_address += 1;
            }
            }
        }
        }
    }
    
    void write_a8_as_i8_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 8);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 8; fine_x++) {
                int x = tile_x * 8 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    u8 alpha = src[src_offset + 3];
                    mem.physical_write_u8(current_address, alpha);
                } else {
                    mem.physical_write_u8(current_address, 0);
                }
                current_address += 1;
            }
            }
        }
        }
    }
    
    int convert_rgba8_to_rgb8(ubyte* src, ubyte* dst, u16 width, u16 height) {
        int dst_idx = 0;
        for (int i = 0; i < width * height; i++) {
            dst[dst_idx++] = 255; // R
            dst[dst_idx++] = src[i * 4 + 1]; // G
            dst[dst_idx++] = src[i * 4 + 2]; // B
            dst[dst_idx++] = 255;
        }
        return dst_idx;
    }
    
    int convert_rgba8_to_rgb565(ubyte* src, ubyte* dst, u16 width, u16 height) {
        int dst_idx = 0;
        for (int i = 0; i < width * height; i++) {
            u8 r = src[i * 4 + 0] >> 3;
            u8 g = src[i * 4 + 1] >> 2;
            u8 b = src[i * 4 + 2] >> 3;
            u16 rgb565 = cast(u16) ((r << 11) | (g << 5) | b);
            dst[dst_idx++] = cast(u8) (rgb565 >> 8);
            dst[dst_idx++] = cast(u8) (rgb565 & 0xFF);
        }
        return dst_idx;
    }
    
    int convert_rgba8_to_rgba6(ubyte* src, ubyte* dst, u16 width, u16 height) {
        int dst_idx = 0;
        for (int i = 0; i < width * height * 4; i += 4) {
            u8 r = src[i + 0] >> 2;
            u8 g = src[i + 1] >> 2;
            u8 b = src[i + 2] >> 2;
            u8 a = src[i + 3] >> 2;
            u32 rgba6 = (r << 18) | (g << 12) | (b << 6) | a;
            dst[dst_idx++] = cast(u8) ((rgba6 >> 16) & 0xFF);
            dst[dst_idx++] = cast(u8) ((rgba6 >> 8) & 0xFF);
            dst[dst_idx++] = cast(u8) (rgba6 & 0xFF);
        }
        return dst_idx;
    }
    
    void write_rgba32_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 4);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            u32 ra_address = current_address;
            u32 gb_address = current_address + 32;
            
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                int x = tile_x * 4 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    u8 r = src[src_offset + 0];
                    u8 g = src[src_offset + 1];
                    u8 b = src[src_offset + 2];
                    u8 a = src[src_offset + 3];
                    
                    mem.physical_write_u8(ra_address + 0, a);
                    mem.physical_write_u8(ra_address + 1, r);
                    mem.physical_write_u8(gb_address + 0, g);
                    mem.physical_write_u8(gb_address + 1, b);
                }
                
                ra_address += 2;
                gb_address += 2;
            }
            }
            
            current_address += 64;
        }
        }
    }
    
    void write_rgb565_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 4);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                int x = tile_x * 4 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    u8 r = src[src_offset + 0] >> 3;  // 5 bits
                    u8 g = src[src_offset + 1] >> 2;  // 6 bits  
                    u8 b = src[src_offset + 2] >> 3;  // 5 bits
                    u16 rgb565 = cast(u16) ((r << 11) | (g << 5) | b);
                    
                    mem.physical_write_u8(current_address + 0, cast(u8)(rgb565 >> 8));
                    mem.physical_write_u8(current_address + 1, cast(u8)(rgb565 & 0xFF));
                }
                current_address += 2;
            }
            }
        }
        }
    }
    
    void write_rgb5a3_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 4);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                int x = tile_x * 4 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    u8 r8 = src[src_offset + 0];
                    u8 g8 = src[src_offset + 1]; 
                    u8 b8 = src[src_offset + 2];
                    u8 a8 = src[src_offset + 3];
                    
                    u16 pixel;
                    if (a8 == 255) { // RGB5 mode (fully opaque)
                        u8 r5 = r8 >> 3;  // 5 bits
                        u8 g5 = g8 >> 3;  // 5 bits
                        u8 b5 = b8 >> 3;  // 5 bits
                        pixel = cast(u16) (0x8000 | (r5 << 10) | (g5 << 5) | b5);
                    } else { // RGBA4 mode (has transparency)
                        u8 r4 = r8 >> 4;  // 4 bits
                        u8 g4 = g8 >> 4;  // 4 bits  
                        u8 b4 = b8 >> 4;  // 4 bits
                        u8 a3 = a8 >> 5;  // 3 bits
                        pixel = cast(u16) ((a3 << 12) | (r4 << 8) | (g4 << 4) | b4);
                    }
                    
                    mem.physical_write_u8(current_address + 0, cast(u8)(pixel >> 8));
                    mem.physical_write_u8(current_address + 1, cast(u8)(pixel & 0xFF));
                }
                current_address += 2;
            }
            }
        }
        }
    }
    
    void write_r8_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 8);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 8; fine_x++) {
                int x = tile_x * 8 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    u8 r = src[src_offset + 0];
                    
                    mem.physical_write_u8(current_address, r);
                }
                current_address += 1;
            }
            }
        }
        }
    }
    
    void write_rg8_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 4);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                int x = tile_x * 4 + fine_x;
                int y = tile_y * 4 + fine_y;
                
                if (x < width && y < height) {
                    int src_offset = (y * width + x) * 4;
                    u8 r = src[src_offset + 0];
                    u8 g = src[src_offset + 1];
                    
                    u16 rg_value = (r << 8) | g;
                    mem.physical_write_u8(current_address + 0, cast(u8)(rg_value >> 8));
                    mem.physical_write_u8(current_address + 1, cast(u8)(rg_value & 0xFF));
                }

                current_address += 2;
            }
            }
        }
        }
    }
    
    void update_gl_viewport() {
        float width = viewport[0] * 2;
        float height = -viewport[1] * 2;
        float x_orig = viewport[3] - 342.0f - viewport[0];
        float y_orig = viewport[4] - 342.0f + viewport[1];
        
        int gl_x = cast(int) x_orig;
        int gl_y = cast(int) y_orig; 
        int gl_width = cast(int) width;
        int gl_height = cast(int) height;
        
        opengl_renderer.update_gl_viewport(gl_x, gl_y, gl_width, gl_height);
    }

    private void update_texture_matrices() {
        auto render_state = get_render_state_for_modification();
        
        for (int i = 0; i < 8; i++) {
            int tex_slot = render_state.texture_descriptors[i].tex_matrix_slot;
            int dualtex_slot = render_state.texture_descriptors[i].dualtex_matrix_slot;
            
            for (int j = 0; j < 12; j++) {
                render_state.vertex_config.tex_configs[i].tex_matrix[j] = general_matrix_ram[tex_slot * 4 + j];
                render_state.vertex_config.tex_configs[i].dualtex_matrix[j] = dt_texture_matrix_ram[dualtex_slot * 4 + j];
            }
            
            render_state.vertex_config.tex_configs[i].normalize_before_dualtex = render_state.texture_descriptors[i].normalize_before_dualtex;
            render_state.vertex_config.tex_configs[i].texcoord_source = render_state.texture_descriptors[i].texcoord_source;
            render_state.vertex_config.tex_configs[i].texmatrix_size = render_state.texture_descriptors[i].texmatrix_size;
            render_state.vertex_config.tex_configs[i].use_stq = render_state.texture_descriptors[i].use_stq;
        }

        render_state.position_matrix = general_matrix_ram[render_state.geometry_matrix_idx * 4 .. render_state.geometry_matrix_idx * 4 + 12];
    }
    
    public GLuint get_xfb_texture() {
        return opengl_renderer.get_xfb_color_texture();
    }
    
    public bool has_xfb_data() {
        return xfb_has_data;
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
        schedule_fifo_processing();
    }
    
    void schedule_fifo_processing() {
        scheduler.add_event_relative_to_clock(&fifo_processing_event, 10_000);
    }
    
    void fifo_processing_event() {
        process_pending_fifo();
        schedule_fifo_processing();
    }

    void write_GX_FIFO(T)(T value, int offset) {
        if (!command_processor.fifos_linked) {
            write_to_pi_fifo(value);
            return;
        }

        log_hollywood("GX FIFO write: %08x %d %d %x %x", value, offset, T.sizeof, mem.cpu.state.pc, mem.cpu.state.lr);
        fifo_write_ptr += T.sizeof;
        while (fifo_write_ptr >= fifo_base_end) {
            fifo_write_ptr -= (fifo_base_end - fifo_base_start);
            fifo_wrapped = true;
        }

        process_fifo_write(value, offset);
    }

    void write_to_pi_fifo(T)(T value) {
        log_hollywood("PI FIFO write: %08x %d %x %x", value, T.sizeof, mem.cpu.state.pc, mem.cpu.state.lr);
        
        static foreach (i; 0 .. T.sizeof) {
            mem.physical_write_u8(cast(u32) (fifo_write_ptr + i) & 0x1fffffff, value.get_byte(T.sizeof - i - 1));
        }
        
        fifo_write_ptr += T.sizeof;
        while (fifo_write_ptr >= fifo_base_end) {
            fifo_write_ptr -= (fifo_base_end - fifo_base_start);
            fifo_wrapped = true;
        }
    }

    T read_from_fifo_data(T)(ubyte* data, ref size_t offset) {
        T value;
        
        static if (T.sizeof == 1) {
            value = data[offset];
        } else static if (T.sizeof == 2) {
            ushort raw_value = *cast(ushort*)(data + offset);
            value = cast(T) bswap(raw_value);
        } else static if (T.sizeof == 4) {
            uint raw_value = *cast(uint*)(data + offset);
            value = cast(T) bswap(raw_value);
        } else static if (T.sizeof == 8) {
            ulong raw_value = *cast(ulong*)(data + offset);
            value = cast(T) bswap(raw_value);
        } else {
            static assert(false, "Unsupported type size");
        }
        
        offset += T.sizeof;

        log_hollywood("read_from_fifo_data: %x", value);

        // fifo_debug_history.add_overwrite(FifoDebugValue(value, state));
        return value;
    }

    void process_fifo_write(T)(T value, int offset) {
        bool watermark_hit = pending_fifo_data.add(value);

        if (watermark_hit) {
            process_pending_fifo();
        }
    }

    size_t process_fifo(ubyte* data, size_t length) {
        size_t offset = 0;
        log_hollywood("Processing GX FIFO data. Length: %d, state: %s", length, state);

        bool handled = false;
        while (offset < length && cached_bytes_needed <= length - offset) {
            log_hollywood("Check passed: %d < %d && %d <= %d", offset, length, cached_bytes_needed, length - offset);
            handled = false;
            final switch (state) {
                case State.WaitingForCommand:
                    if (offset + 1 <= length) {
                        handle_new_command(read_from_fifo_data!u8(data, offset));
                        handled = true;
                    }

                    break;

                case State.WaitingForBPWrite:
                    if (offset + 4 <= length) {
                        handle_new_bp_write(read_from_fifo_data!u32(data, offset));
                        state = State.WaitingForCommand;
                        cached_bytes_needed = 1;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForCPReg:
                    if (offset + 1 <= length) {
                        cp_register = read_from_fifo_data!u8(data, offset);
                        state = State.WaitingForCPData;
                        cached_bytes_needed = 4;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForCPData:
                    if (offset + 4 <= length) {
                        handle_new_cp_write(cp_register, read_from_fifo_data!u32(data, offset));
                        state = State.WaitingForCommand;
                        cached_bytes_needed = 1;
                        handled = true;
                    }

                    break;

                case State.WaitingForTransformUnitDescriptor:
                    if (offset + 4 <= length) {
                        u32 data_value   = read_from_fifo_data!u32(data, offset);
                        xf_register       = cast(u16)  data_value.bits(0, 15);
                        xf_data_remaining = cast(u16) (data_value.bits(16, 31) + 1);

                        state = State.WaitingForTransformUnitData;
                        cached_bytes_needed = 4;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForTransformUnitData:
                    if (offset + 4 <= length) {
                        handle_new_transform_unit_write(xf_register, read_from_fifo_data!u32(data, offset));

                        xf_data_remaining -= 1;
                        xf_register += 1;

                        if (xf_data_remaining == 0) {
                            state = State.WaitingForCommand;
                            cached_bytes_needed = 1;
                        } else {
                            cached_bytes_needed = 4;
                        }

                        handled = true;
                    }

                    break;

                case State.WaitingForLoadMtxIdxData:
                    if (offset + 4 <= length) {
                        u32 param = read_from_fifo_data!u32(data, offset);

                        // if (current_load_mtx_idx == 0) {
                            int address = param.bits(0, 11);
                            int size    = param.bits(12, 15) + 1;
                            int mtxidx  = param.bits(16, 31);

                            u32 src_addr = array_bases[12 + current_load_mtx_idx] + (array_strides[12 + current_load_mtx_idx] * mtxidx);

                            for (int i = 0; i < size; i++) {
                                u32 float_bits = mem.physical_read_u32(src_addr + i * 4);
                                
                                // TODO: fixme
                                if (address + i <= 0xff) {
                                    general_matrix_ram[address + i] = force_cast!float(float_bits);
                                }
                            }
                        // }
                        
                        state = State.WaitingForCommand;
                        cached_bytes_needed = 1;
                        handled = true;
                    }

                    break;
                
                case State.WaitingForNumberOfVertices:
                    if (offset + 2 <= length) {
                        u16 data_value = read_from_fifo_data!u16(data, offset);
                        number_of_expected_vertices = data_value;
                        number_of_expected_bytes_for_shape = size_of_incoming_vertex(current_vat) * number_of_expected_vertices;
                        state = State.WaitingForVertexData;
                        cached_bytes_needed = number_of_expected_bytes_for_shape;
                        log_hollywood("vat: %s", vats[current_vat]);
                        log_hollywood("vcd: %s", vertex_descriptors[0]);
                        log_hollywood("Number of vertices: %d", number_of_expected_vertices);
                        log_hollywood("Number of expected bytes for shape: %d", number_of_expected_bytes_for_shape);
                        handled = true;
                    }

                    break;
                
                case State.WaitingForVertexData:
                    size_t remaining_data = length - offset;

                    if (remaining_data >= number_of_expected_bytes_for_shape) {
                        process_new_shape_from_data(data + offset, number_of_expected_bytes_for_shape);
                        offset += number_of_expected_bytes_for_shape;
                        state = State.WaitingForCommand;
                        cached_bytes_needed = 1;
                        number_of_received_bytes_for_shape = 0;
                        handled = true;
                    } else if (remaining_data > number_of_expected_bytes_for_shape) {
                        error_hollywood("Received too many bytes for shape");
                    }

                    break;
                
                case State.WaitingForDisplayListAddress:
                    if (offset + 4 <= length) {
                        u32 address = read_from_fifo_data!u32(data, offset);
                        log_hollywood("Display list address: %08x", address);
                        this.display_list_address = address;
                        state = State.WaitingForDisplayListSize;
                        cached_bytes_needed = 4;
                        handled = true;
                    } else {
                        error_hollywood("Unexpected GX FIFO write A");
                    }

                    break;
                
                case State.WaitingForDisplayListSize:
                    if (offset + 4 <= length) {
                        u32 size = read_from_fifo_data!u32(data, offset);
                        log_hollywood("Display list size: %08x", size);
                        this.display_list_size = size;
                        state = State.WaitingForCommand;
                        cached_bytes_needed = 1;
                        process_display_list(this.display_list_address, this.display_list_size);
                        handled = true;
                    } else {
                        error_hollywood("Unexpected GX FIFO write B");
                    }

                    break;
            }

            if (!handled) break;
        }

        if (offset < length) {
            log_hollywood("Unprocessed data remains: %d bytes", length - offset);
        }

        return offset;
    }

    void process_pending_fifo() {
        size_t available = pending_fifo_data.get_size();
        if (available < cached_bytes_needed) return;
        
        ubyte* data = pending_fifo_data.buffer + pending_fifo_data.read_ptr;
        size_t initial_read_ptr = pending_fifo_data.read_ptr;
        
        size_t processed = process_fifo(data, available);
        pending_fifo_data.read_ptr = initial_read_ptr + processed;
        pending_fifo_data.wrap_pointers();
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
            case State.WaitingForLoadMtxIdxData:
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
        auto command = cast(GXFifoCommand) value.bits(0, 7);

        switch (cast(int) command) {
            case GXFifoCommand.BlittingProcessor: 
                state = State.WaitingForBPWrite; cached_bytes_needed = 4; break;
            case GXFifoCommand.CommandProcessor:  
                state = State.WaitingForCPReg; cached_bytes_needed = 1; break;
            case GXFifoCommand.TransformUnit:     
                state = State.WaitingForTransformUnitDescriptor; cached_bytes_needed = 4; break;
            case GXFifoCommand.LoadMtxIdxA: .. case GXFifoCommand.LoadMtxIdxD:
                current_load_mtx_idx = (cast(int) command).bits(3, 4);
                state = State.WaitingForLoadMtxIdxData; 
                cached_bytes_needed = 4; 
                break;
            case GXFifoCommand.VSInvalidate:      
                log_hollywood("Unimplemented: VS invalidate"); break;
            case GXFifoCommand.NoOp:              
                break;
            
            case GXFifoCommand.DrawQuads | 0: .. case GXFifoCommand.DrawQuads | 7:         
                current_draw_command = GXFifoCommand.DrawQuads;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawTriangles | 0: .. case GXFifoCommand.DrawTriangles | 7:
                current_draw_command = GXFifoCommand.DrawTriangles;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawTriangleFan | 0: .. case GXFifoCommand.DrawTriangleFan | 7:
                current_draw_command = GXFifoCommand.DrawTriangleFan;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawTriangleStrip | 0: .. case GXFifoCommand.DrawTriangleStrip | 7:
                current_draw_command = GXFifoCommand.DrawTriangleStrip;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawLines | 0: .. case GXFifoCommand.DrawLines | 7:
                current_draw_command = GXFifoCommand.DrawLines;
                current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vats[current_vat]);
                log_hollywood("vcd: %s", vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DisplayList:
                state = State.WaitingForDisplayListAddress;
                cached_bytes_needed = 4;
                break;
        
            default:
                error_hollywood("Unknown GX command: %02x", command);
                break;
        }
    }

    private void process_display_list(u32 address, u32 size) {
        address &= 0x1FFF_FFFF;

        ubyte* ptr = mem.translate_address(address);
        process_fifo(ptr, size);
    }
    

    void handle_new_bp_write(u32 value) {
        auto bp_register = value.bits(24, 31);
        auto bp_data = value.bits(0, 23);

        auto current_value = bp_registers[bp_register];
        auto masked_new_bits = bp_data & next_bp_mask;
        auto preserved_old_bits = current_value & ~next_bp_mask;
        auto final_value = masked_new_bits | preserved_old_bits;
        
        bp_registers[bp_register] = final_value;
        bp_data = final_value;
        next_bp_mask = 0x00ff_ffff;

        switch (bp_register) {
            case 0x40:
                get_render_state_for_modification().depth_test_enabled = bp_data.bit(0);
                get_render_state_for_modification().depth_write_enabled = bp_data.bit(4);

                final switch (bp_data.bits(1, 3)) {
                    case 0: get_render_state_for_modification().depth_func = GL_NEVER; break;
                    case 1: get_render_state_for_modification().depth_func = GL_LESS; break;
                    case 2: get_render_state_for_modification().depth_func = GL_EQUAL; break;
                    case 3: get_render_state_for_modification().depth_func = GL_LEQUAL; break;
                    case 4: get_render_state_for_modification().depth_func = GL_GREATER; break;
                    case 5: get_render_state_for_modification().depth_func = GL_NOTEQUAL; break;
                    case 6: get_render_state_for_modification().depth_func = GL_GEQUAL; break;
                    case 7: get_render_state_for_modification().depth_func = GL_ALWAYS; break;
                }

                break;
            
            case 0x41:
                auto render_state = get_render_state_for_modification();

                render_state.color_update_enable = bp_data.bit(3);
                render_state.alpha_update_enable = bp_data.bit(4);
                render_state.arithmetic_blending_enable = bp_data.bit(0);
                render_state.blend_destination = cast(int) bp_data.bits(5, 7);
                render_state.blend_source = cast(int) bp_data.bits(8, 10);
                render_state.subtractive_additive_toggle = bp_data.bit(11);
                break;

            case 0x49:
                auto render_state = get_render_state_for_modification();
                render_state.efb_src_x = cast(u16) bp_data.bits(0, 9);
                render_state.efb_src_y = cast(u16) bp_data.bits(10, 21);
                break;
            
            case 0x4a:
                auto render_state = get_render_state_for_modification();
                render_state.efb_src_w = cast(u16) (bp_data.bits(0, 9) + 1);
                render_state.efb_src_h = cast(u16) (bp_data.bits(10, 21) + 1);
                break;
            
            case 0x4b:
                xfb_addr = bp_data << 5;
                break;
            
            case 0x4d:
                xfb_stride = bp_data.bits(0, 9);
                break;
            
            case 0x52:
                u8 format_bits_4_6 = cast(u8) bp_data.bits(4, 6);
                u8 format_bit_3 = cast(u8) bp_data.bit(3);
                u8 tex_copy_format = cast(u8) (format_bits_4_6 | (format_bit_3 << 3));
                bool clear_efb = bp_data.bit(11);
                this.tex_copy_format = tex_copy_format;
                execute_efb_copy(bp_data, clear_efb);
                break;
            
            case 0x4F:
                auto render_state = get_render_state_for_modification();
                render_state.clear_color_alpha = cast(u8) bp_data.bits(8, 15);
                render_state.clear_color_red = cast(u8) bp_data.bits(0, 7);
                break;

            case 0x50:
                auto render_state = get_render_state_for_modification();
                render_state.clear_color_green = cast(u8) bp_data.bits(8, 15);
                render_state.clear_color_blue = cast(u8) bp_data.bits(0, 7);
                break;
                
            case 0x51:
                auto render_state = get_render_state_for_modification();
                render_state.clear_depth = bp_data;
                break;
            
            case 1:
                break;
            
            case 2:
                break;
            
            case 3:
                break;
            
            case 4:
                break;
            
            case 0x53:
                break;
            
            case 0x54:
                break;
            
            case 0x20:
                break;
            
            case 0x21:
                break;
            
            case 0x59:
                break;
            
            case 0x00:
                auto render_state = get_render_state_for_modification();

                render_state.tev_config.num_tev_stages = bp_data.bits(10, 13) + 1;
                render_state.cull_mode = bp_data.bits(14, 15);
                log_hollywood("GEN_MODE: %08x", bp_data);
                break;

            case 0x94: .. case 0x97:
                auto render_state = get_render_state_for_modification();

                render_state.texture_descriptors[bp_register - 0x94].base_address = bp_data << 5;
                break;
            
            case 0xb4: .. case 0xb7:
                auto render_state = get_render_state_for_modification();

                render_state.texture_descriptors[bp_register - 0xb4 + 4].base_address = bp_data << 5;
                break;
            
            case 0x88: .. case 0x8b:
                auto render_state = get_render_state_for_modification();

                render_state.texture_descriptors[bp_register - 0x88].width  = bp_data.bits(0, 9) + 1;
                render_state.texture_descriptors[bp_register - 0x88].height = bp_data.bits(10, 19) + 1;
                render_state.texture_descriptors[bp_register - 0x88].type   = cast(TextureType) bp_data.bits(20, 23);
                break;
            
            case 0xa8: .. case 0xab:
                auto render_state = get_render_state_for_modification();

                render_state.texture_descriptors[bp_register - 0xa8 + 4].width  = bp_data.bits(0, 9) + 1;
                render_state.texture_descriptors[bp_register - 0xa8 + 4].height = bp_data.bits(10, 19) + 1;
                render_state.texture_descriptors[bp_register - 0xa8 + 4].type   = cast(TextureType) bp_data.bits(20, 23);
                break;

            case 0x10: .. case 0x1f:
                break;
            
            case 0x28: .. case 0x2f:
                auto render_state = get_render_state_for_modification();
                
                int idx = (bp_register - 0x28);
                render_state.tev_config.stages[idx * 2 + 0].texmap        = bp_data.bits(0, 2);
                render_state.tev_config.stages[idx * 2 + 0].texcoord      = bp_data.bits(3, 5);
                render_state.tev_config.stages[idx * 2 + 0].texmap_enable = bp_data.bit(6);
                render_state.tev_config.stages[idx * 2 + 0].ras_channel_id = bp_data.bits(7, 9);
                render_state.tev_config.stages[idx * 2 + 1].texmap        = bp_data.bits(12, 14);
                render_state.tev_config.stages[idx * 2 + 1].texcoord      = bp_data.bits(15, 17);
                render_state.tev_config.stages[idx * 2 + 1].texmap_enable = bp_data.bit(18);
                render_state.tev_config.stages[idx * 2 + 1].ras_channel_id = bp_data.bits(19, 21);
                break;
            
            case 0xc0: .. case 0xdf:
                auto render_state = get_render_state_for_modification();
                
                if (bp_register.bit(0)) {
                    log_hollywood("TEV_ALPHA_ENV_%x: %08x (tev op 1) at pc 0x%08x", bp_register - 0xc1, bp_data, mem.cpu.state.pc);
                    int idx = (bp_register - 0xc1) / 2;
                    
                    u32 bias = bp_data.bits(16, 17);
                    u32 scale = bp_data.bits(20, 21);
                    render_state.tev_config.stages[idx].in_alfa_a = bp_data.bits(13, 15);
                    render_state.tev_config.stages[idx].in_alfa_b = bp_data.bits(10, 12);
                    render_state.tev_config.stages[idx].in_alfa_c = bp_data.bits(7, 9);
                    render_state.tev_config.stages[idx].in_alfa_d = bp_data.bits(4, 6);

                    if (bias == 3) {
                        render_state.tev_config.stages[idx].alfa_op = 0x8 | (bp_data.bit(18)) | (scale << 1);
                    } else {
                        render_state.tev_config.stages[idx].alfa_op = bp_data.bit(18);
                    }

                    render_state.tev_config.stages[idx].bias_alfa = 
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5;
                    render_state.tev_config.stages[idx].alfa_dest = bp_data.bits(22, 23);
                    render_state.tev_config.stages[idx].clamp_alfa = bp_data.bit(19);

                    render_state.tev_config.stages[idx].scale_alfa = 
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5;

                    log_hollywood("Set indices to %d %d", bp_data.bits(0, 1), bp_data.bits(2, 3));
                    render_state.tev_config.stages[idx].ras_swap_table_index = bp_data.bits(0, 1);
                    render_state.tev_config.stages[idx].tex_swap_table_index = bp_data.bits(2, 3);
                    break;
                } else {
                    int idx = (bp_register - 0xc0) / 2;

                    u32 bias = bp_data.bits(16, 17);
                    u32 scale = bp_data.bits(20, 21);
                    render_state.tev_config.stages[idx].in_color_a = bp_data.bits(12, 15);
                    render_state.tev_config.stages[idx].in_color_b = bp_data.bits(8, 11);
                    render_state.tev_config.stages[idx].in_color_c = bp_data.bits(4, 7);
                    render_state.tev_config.stages[idx].in_color_d = bp_data.bits(0, 3);

                    if (bias == 3) {
                        render_state.tev_config.stages[idx].color_op = 0x8 | (bp_data.bit(18)) | (scale << 1);
                    } else {
                        render_state.tev_config.stages[idx].color_op = bp_data.bit(18);
                    }

                    render_state.tev_config.stages[idx].bias_color = 
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5;
                    render_state.tev_config.stages[idx].clamp_color = bp_data.bit(19);
                    render_state.tev_config.stages[idx].color_dest = bp_data.bits(22, 23);

                    render_state.tev_config.stages[idx].scale_color = 
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5;
                }
                break;
            
            case 0xe0: .. case 0xe7:
                auto render_state = get_render_state_for_modification();
                
                if (bp_data.bit(23)) {
                    int idx = (bp_register - 0xe0) / 2;
                    if (bp_register.bit(0)) {
                        final switch (idx) {
                        case 0: 
                            render_state.tev_config.k0[2] = bp_data.bits(0,   7) / 255.0f; 
                            render_state.tev_config.k0[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 1:
                            render_state.tev_config.k1[2] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.k1[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 2:
                            render_state.tev_config.k2[2] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.k2[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 3:
                            render_state.tev_config.k3[2] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.k3[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        }
                    } else {
                        final switch (idx) {
                        case 0: 
                            render_state.tev_config.k0[0] = bp_data.bits(0,   7) / 255.0f; 
                            render_state.tev_config.k0[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 1:
                            render_state.tev_config.k1[0] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.k1[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 2:
                            render_state.tev_config.k2[0] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.k2[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 3:
                            render_state.tev_config.k3[0] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.k3[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        }
                    }
                } else {
                    if (bp_register.bit(0)) {
                        int idx = (bp_register - 0xe1) / 2;
                        // i dont trust D's memory layout
                        final switch (idx) {
                        case 0: 
                            render_state.tev_config.reg0[2] = bp_data.bits(0,   7) / 255.0f; 
                            render_state.tev_config.reg0[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 1:
                            render_state.tev_config.reg1[2] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.reg1[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 2:
                            render_state.tev_config.reg2[2] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.reg2[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 3:
                            render_state.tev_config.reg3[2] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.reg3[1] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        }
                    } else {
                        int idx = (bp_register - 0xe0) / 2;
                        // i dont trust D's memory layout
                        final switch (idx) {
                        case 0: 
                            render_state.tev_config.reg0[0] = bp_data.bits(0,   7) / 255.0f; 
                            render_state.tev_config.reg0[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 1:
                            render_state.tev_config.reg1[0] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.reg1[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 2:
                            render_state.tev_config.reg2[0] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.reg2[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        case 3:
                            render_state.tev_config.reg3[0] = bp_data.bits(0,   7) / 255.0f;
                            render_state.tev_config.reg3[3] = bp_data.bits(12, 19) / 255.0f;
                            break;
                        }
                    }
                }
                break;
       
            case 0xee: .. case 0xf1:
                log_hollywood("TEV_FOG_PARAM_%x: %08x", bp_register - 0xee, bp_data);
                break;

            case 0xf3:
                auto render_state = get_render_state_for_modification();
                
                render_state.alpha_comp0 = cast(u8) bp_data.bits(16, 18);
                render_state.alpha_comp1 = cast(u8) bp_data.bits(19, 21);
                render_state.alpha_aop = cast(u8) bp_data.bits(22, 23);
                render_state.alpha_ref0 = cast(u8) bp_data.bits(0, 7);
                render_state.alpha_ref1 = cast(u8) bp_data.bits(8, 15);
                render_state.tev_config.alpha_comp0 = render_state.alpha_comp0;
                render_state.tev_config.alpha_comp1 = render_state.alpha_comp1;
                render_state.tev_config.alpha_aop = render_state.alpha_aop;
                render_state.tev_config.alpha_ref0 = render_state.alpha_ref0;
                render_state.tev_config.alpha_ref1 = render_state.alpha_ref1;
                break;
            
            case 0xf4: .. case 0xf5:
                log_hollywood("TEV_Z_ENV_%x: %08x", bp_register - 0xf4, bp_data);
                break;

            case 0x80: .. case 0x83:
                auto render_state = get_render_state_for_modification();
                
                render_state.texture_descriptors[bp_register - 0x80].wrap_s = cast(TextureWrap) bp_data.bits(0, 1);
                render_state.texture_descriptors[bp_register - 0x80].wrap_t = cast(TextureWrap) bp_data.bits(2, 3);
                break;

            case 0xa0: .. case 0xa3:
                auto render_state = get_render_state_for_modification();
                
                render_state.texture_descriptors[bp_register - 0xa0 + 4].wrap_s = cast(TextureWrap) bp_data.bits(0, 1);
                render_state.texture_descriptors[bp_register - 0xa0 + 4].wrap_t = cast(TextureWrap) bp_data.bits(2, 3);
                break;
            
            case 0x45:
                log_hollywood("PE interrupt: %08x", bp_data);
                scheduler.add_event_relative_to_clock(() { pixel_engine.raise_finish_interrupt(); }, 1_000_000);
                break;

            case 0x43:
                pixel_engine.pe_cntrl = bp_data;
                log_hollywood("PE_CNTRL: %08x, EFB format: %d", bp_data, pixel_engine.get_efb_pixel_format());
                break;

            case 0x47:
                log_hollywood("tokenize interrupt: %08x", bp_data);
                scheduler.add_event_relative_to_clock(() { pixel_engine.raise_token_interrupt(cast(u16) bp_data.bits(0, 15)); }, 1_000_000);
                break;
            
            case 0xf6:
            case 0xf8:
            case 0xfa:
            case 0xfc:
                auto render_state = get_render_state_for_modification();
                
                log_texture("TEV_SWAP_MODE_TABLE_%02x: %08x", bp_register, bp_data);
                int idx = (bp_register - 0xf6) / 2;
                render_state.tev_config.swap_tables &= ~(0xf << (idx * 8));
                render_state.tev_config.swap_tables |= value.bits(0, 3) << (idx * 8);
                render_state.tev_config.stages[idx * 4 + 0].kcsel = value.bits(4, 8);
                render_state.tev_config.stages[idx * 4 + 0].kasel = value.bits(9, 13);
                render_state.tev_config.stages[idx * 4 + 1].kcsel = value.bits(14, 18);
                render_state.tev_config.stages[idx * 4 + 1].kasel = value.bits(19, 23);
                assert_texture(render_state.tev_config.stages[idx * 4 + 0].kasel != 12, "Invalid kcsel");
                assert_texture(render_state.tev_config.stages[idx * 4 + 1].kasel != 12, "Invalid kcsel");
                break;

            case 0xf7:
            case 0xf9:
            case 0xfb:
            case 0xfd:
                log_texture("TEV_SWAP_MODE_TABLE_%02x: %08x", bp_register, bp_data);
                auto render_state = get_render_state_for_modification();
                int idx = (bp_register - 0xf6) / 2;
                render_state.tev_config.swap_tables &= ~(0xf << (idx * 8 + 4));
                render_state.tev_config.swap_tables |= bp_data.bits(0, 3) << (idx * 8 + 4);
                render_state.tev_config.stages[idx * 4 + 2].kcsel = bp_data.bits(4, 8);
                render_state.tev_config.stages[idx * 4 + 2].kasel = bp_data.bits(9, 13);
                render_state.tev_config.stages[idx * 4 + 3].kcsel = bp_data.bits(14, 18);
                render_state.tev_config.stages[idx * 4 + 3].kasel = bp_data.bits(19, 23);
                assert_texture(render_state.tev_config.stages[idx * 4 + 2].kasel != 12, "Invalid kcsel");
                assert_texture(render_state.tev_config.stages[idx * 4 + 3].kasel != 12, "Invalid kcsel");
                break;
            
            case 0xfe:
                next_bp_mask = bp_data;
                break;

            default:
                log_hollywood("Unimplemented: BP register %02x", bp_register);
                break;
        }
    }

    void handle_new_cp_write(u8 register, u32 value) {
        switch (register) {
            case 0x30:
                auto render_state = get_render_state_for_modification();
                
                render_state.geometry_matrix_idx = value.bits(0, 5);
                break;

            case 0x50: .. case 0x57:
                auto vcd = &vertex_descriptors[register - 0x50];
                
                vcd.position_normal_matrix_location = cast(VertexAttributeLocation) value.bit(0);
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
                
                auto render_state = get_render_state_for_modification();
                render_state.uses_per_vertex_matrices = (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent);

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
            
            case 0xa0: .. case 0xaf:
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
        auto vcd = &vertex_descriptors[0];
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
                size += 1;
                // error_hollywood("Direct Matrix location not implemented");
                break;
    
            case VertexAttributeLocation.Indexed8Bit:
            case VertexAttributeLocation.Indexed16Bit: 
                error_hollywood("Indexed Matrix location not implemented"); break;
            case VertexAttributeLocation.NotPresent: break;
        }

        for (int i = 0; i < 8; i++) {
            final switch (vcd.texcoord_matrix_location[i]) {
                case VertexAttributeLocation.Direct:
                    // error_hollywood("Direct Matrix location not implemented");
                    size += 1;
                    break;

                case VertexAttributeLocation.Indexed8Bit:
                case VertexAttributeLocation.Indexed16Bit:
                    error_hollywood("Indexed Matrix location not implemented"); break;
                
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
                get_render_state_for_modification().geometry_matrix_idx = value.bits(0, 5);
                get_render_state_for_modification().texture_descriptors[0].tex_matrix_slot = value.bits(6, 11);
                get_render_state_for_modification().texture_descriptors[1].tex_matrix_slot = value.bits(12, 17);
                get_render_state_for_modification().texture_descriptors[2].tex_matrix_slot = value.bits(18, 23);
                get_render_state_for_modification().texture_descriptors[3].tex_matrix_slot = value.bits(24, 29);
                break;

            case 0x1019:
                get_render_state_for_modification().texture_descriptors[4].tex_matrix_slot = value.bits(0, 5);
                get_render_state_for_modification().texture_descriptors[5].tex_matrix_slot = value.bits(6, 11);
                get_render_state_for_modification().texture_descriptors[6].tex_matrix_slot = value.bits(12, 17);
                get_render_state_for_modification().texture_descriptors[7].tex_matrix_slot = value.bits(18, 23);
                break;

            case 0x101a: viewport[0] = force_cast!float(value); update_gl_viewport(); break;
            case 0x101b: viewport[1] = force_cast!float(value); update_gl_viewport(); break;
            case 0x101c: viewport[2] = force_cast!float(value); update_gl_viewport(); break;
            case 0x101d: viewport[3] = force_cast!float(value); update_gl_viewport(); break;
            case 0x101e: viewport[4] = force_cast!float(value); update_gl_viewport(); break;
            case 0x101f: viewport[5] = force_cast!float(value); update_gl_viewport(); break;
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
                get_render_state_for_modification().texture_descriptors[idx].texmatrix_size  = cast(TexcoordSource) value.bit(1) ? 3 : 2;
                get_render_state_for_modification().texture_descriptors[idx].use_stq         = cast(TexcoordSource) value.bit(2);
                get_render_state_for_modification().texture_descriptors[idx].texcoord_source = cast(TexcoordSource) value.bits(7, 11);
                break;

            case 0x0000: .. case 0x00ff:
                general_matrix_ram[register] = force_cast!float(value);
                break;
            
            case 0x0500: .. case 0x05ff:
                dt_texture_matrix_ram[register - 0x500] = force_cast!float(value);
                break;
            
            case 0x1050: .. case 0x1057:
                int idx = register - 0x1050;

                get_render_state_for_modification().texture_descriptors[idx].dualtex_matrix_slot = value.bits(0, 5);
                get_render_state_for_modification().texture_descriptors[idx].normalize_before_dualtex = value.bit(7);
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
        auto render_state = get_render_state_for_modification();
    
        final switch (projection_mode) {
            case ProjectionMode.Perspective:
                render_state.projection_matrix = [
                    p[0], 0,    0,     0,
                    0,    p[2], 0,     0,
                    p[1], p[3], p[4], -1,
                    0,    0,    p[5],  0
                ];
                break;
            
            case ProjectionMode.Orthographic:
                render_state.projection_matrix = [
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
                return force_cast!float(value) / (cast(float) (1 << shift));
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

    private u32 get_vertex_attribute_from_data(VertexAttributeLocation location, ubyte* data, size_t offset, size_t size, int arr_idx) {
        u32 result = 0;

        switch (location) {
            case VertexAttributeLocation.Indexed8Bit:
                // data = read_from_indexed_array(arr_idx, read_from_shape_data_buffer_direct(data, offset, 1), size);
                break;
            case VertexAttributeLocation.Indexed16Bit:
                // data = read_from_indexed_array(arr_idx, read_from_shape_data_buffer_direct(data, offset, 2), size);
                break;
            case VertexAttributeLocation.Direct:
                result = read_from_shape_data_buffer_direct(data, offset, size);
                break;
            default:
                error_hollywood("Unimplemented vertex attribute location");
        }

        return result;
    }

    private u32 read_from_shape_data_buffer_direct(ubyte* data, size_t offset, size_t size) {
        u32 result = 0;
        for (int i = 0; i < size; i++) {
            result <<= 8;
            result |= data[offset + i];
        }

        log_hollywood("read_from_shape_data_buffer_direct: %x %x", result, size);
        return result;
    }

    private u32 read_from_indexed_array(int array_num, int idx, int offset, size_t size) {
        u32 array_addr = array_bases[array_num];
        u32 array_stride = array_strides[array_num];
        u32 array_offset = array_addr + (array_stride * idx) + (offset * cast(int) size);

        final switch (size) {
        case 1: return mem.physical_read_u8(array_offset);
        case 2: return mem.physical_read_u16(array_offset);
        case 4: return mem.physical_read_u32(array_offset);
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

    private void process_new_shape_from_data(ubyte* data, size_t data_length) {
        update_texture_matrices();
        
        auto render_state = get_render_state_for_modification();
        for (int i = 0; i < 8; i++) {
            if (render_state.tev_config.stages[i].texmap_enable) {
                auto j = render_state.tev_config.stages[i].texmap;
                render_state.texture[j].texture_id = texture_manager.load_texture(render_state.texture_descriptors[j], mem, gl_object_manager);
                render_state.enabled_textures_bitmap |= (1 << i);
            }
        }

        if (accumulated_geometry.shared_index_count == 0) {
            accumulated_geometry.shared_vertex_start = opengl_renderer.get_current_vertex_offset();
            accumulated_geometry.shared_index_start = opengl_renderer.get_current_index_offset();
        }

        int offset = 0;
        auto vcd = &vertex_descriptors[0];
        auto vat = &vats[current_vat];

        auto decode_vertex = () {
            Vertex v;

            if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
                v.position_matrix_index = read_from_shape_data_buffer_direct(data, offset, 1);
                offset += 1;
            } else {
                v.position_matrix_index = -1;
                // Don't modify render state here
            }

            for (int j = 0; j < 8; j++) {
                if (vcd.texcoord_matrix_location[j] != VertexAttributeLocation.NotPresent) {
                    offset += 1;
                }
            }
            
            final switch (vcd.position_location) {
            case VertexAttributeLocation.Direct:
                for (int j = 0; j < vat.position_count; j++) {
                    v.position[j] = dequantize_coord(
                        read_from_shape_data_buffer_direct(data, offset, calculate_expected_size_of_coord(vat.position_format)),
                        vat.position_format, vat.position_shift);
                    offset += calculate_expected_size_of_coord(vat.position_format);
                }
                break;
            case VertexAttributeLocation.Indexed8Bit:
                auto array_offset = read_from_shape_data_buffer_direct(data, offset, 1);
                for (int j = 0; j < vat.position_count; j++) {
                    size_t size = calculate_expected_size_of_coord(vat.position_format);
                    log_hollywood("processing position with size %d", size);
                    u32 vertex_data = read_from_indexed_array(0, array_offset, j, size);
                    v.position[j] = dequantize_coord(vertex_data, vat.position_format, vat.position_shift);
                }
                offset += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                auto array_offset = read_from_shape_data_buffer_direct(data, offset, 2);
                for (int j = 0; j < vat.position_count; j++) {
                    size_t size = calculate_expected_size_of_coord(vat.position_format);
                    log_hollywood("processing position with size %d", size);
                    u32 vertex_data = read_from_indexed_array(0, array_offset, j, size);
                    v.position[j] = dequantize_coord(vertex_data, vat.position_format, vat.position_shift);
                }
                offset += 2;
                break;
            case VertexAttributeLocation.NotPresent:
                break;
            }

            if (vat.position_count == 2) {
                v.position[2] = 0.0;
            }

            final switch (vcd.normal_location) {
            case VertexAttributeLocation.Direct:
                size_t size = calculate_expected_size_of_normal(vat.normal_format);
                for (int j = 0; j < vat.normal_count; j++) {
                    read_from_shape_data_buffer_direct(data, offset, size);
                    offset += size;
                }
                break;
            case VertexAttributeLocation.Indexed8Bit:
                read_from_shape_data_buffer_direct(data, offset, 1);
                offset += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                read_from_shape_data_buffer_direct(data, offset, 2);
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
                    u32 color_data = get_vertex_attribute_from_data(vcd.color_location[j], data, offset, size, j + 2);
                    color = dequantize_color(color_data, vat.color_format[j], j);

                    if (vat.color_count[j] == 3) {
                        color[3] = 1.0;
                    }

                    offset += get_size_of_vertex_attribute_in_stream(vcd.color_location[j], size);
                    break;
                
                case VertexAttributeLocation.Indexed8Bit:
                        auto array_offset = read_from_shape_data_buffer_direct(data, offset, 1);
                    size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                    log_hollywood("processing color with size %d", size);

                    u32 color_data = read_from_indexed_array(j + 2, array_offset, 0, size);
                    color = dequantize_color(color_data, vat.color_format[j], j);

                    if (vat.color_count[j] == 3) {
                        color[3] = 1.0;
                    }

                    offset += 1;
                    break;
                
                case VertexAttributeLocation.Indexed16Bit:
                        auto array_offset = read_from_shape_data_buffer_direct(data, offset, 2);
                    size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                    log_hollywood("processing color with size %d", size);

                    u32 color_data = read_from_indexed_array(j + 2, array_offset, 0, size);
                    color = dequantize_color(color_data, vat.color_format[j], j);

                    if (vat.color_count[j] == 3) {
                        color[3] = 1.0;
                    }

                    offset += 2;
                    break;
                
                case VertexAttributeLocation.NotPresent:
                    color = [1.0, 1.0, 1.0, 1.0];
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

            for (int j = 0; j < 8; j++) {
                final switch (vcd.texcoord_location[j]) {
                case VertexAttributeLocation.Direct:
                    log_hollywood("processing texcoord with size %d", vat.texcoord_count[j]);
                    for (int k = 0; k < vat.texcoord_count[j]; k++) {
                        size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                        u32 texcoord = get_vertex_attribute_from_data(vcd.texcoord_location[j], data, offset, size, j + 4);
                        v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                        offset += get_size_of_vertex_attribute_in_stream(vcd.texcoord_location[j], size);
                    }
                    break;
                
                case VertexAttributeLocation.Indexed8Bit:
                        auto array_offset = read_from_shape_data_buffer_direct(data, offset, 1);
                    log_hollywood("processing texcoord with size %d", vat.texcoord_count[j]);
                    for (int k = 0; k < vat.texcoord_count[j]; k++) {
                        size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                        u32 texcoord = read_from_indexed_array(j + 4, array_offset, k, size);
                        v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                    }
                    offset += 1;
                    break;

                case VertexAttributeLocation.Indexed16Bit:
                        auto array_offset = read_from_shape_data_buffer_direct(data, offset, 2);
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

            return v;
        };

        switch (current_draw_command) {
        case GXFifoCommand.DrawQuads: {
            uint[4] quad_indices;
            int quad_count = 0;
            for (int i = 0; i < number_of_expected_vertices; i++) {
                Vertex v = decode_vertex();
                uint local_idx = cast(uint) (opengl_renderer.get_current_vertex_offset() - accumulated_geometry.shared_vertex_start);
                *next_vertex() = v;
                quad_indices[quad_count++] = local_idx;
                if (quad_count == 4) {
                    *next_index() = quad_indices[0];
                    *next_index() = quad_indices[1];
                    *next_index() = quad_indices[2];
                    *next_index() = quad_indices[0];
                    *next_index() = quad_indices[2];
                    *next_index() = quad_indices[3];
                    quad_count = 0;
                }
            }
            break;
        }

        case GXFifoCommand.DrawTriangles: {
            uint[3] tri;
            int tri_count = 0;
            for (int i = 0; i < number_of_expected_vertices; i++) {
                Vertex v = decode_vertex();
                uint local_idx = cast(uint) (opengl_renderer.get_current_vertex_offset() - accumulated_geometry.shared_vertex_start);
                *next_vertex() = v;
                tri[tri_count++] = local_idx;
                if (tri_count == 3) {
                    *next_index() = tri[0];
                    *next_index() = tri[1];
                    *next_index() = tri[2];
                    tri_count = 0;
                }
            }
            break;
        }

        case GXFifoCommand.DrawTriangleFan: {
            uint first_idx = uint.max;
            uint prev_idx = uint.max;
            for (int i = 0; i < number_of_expected_vertices; i++) {
                Vertex v = decode_vertex();
                uint local_idx = cast(uint) (opengl_renderer.get_current_vertex_offset() - accumulated_geometry.shared_vertex_start);
                *next_vertex() = v;

                if (first_idx == uint.max) {
                    first_idx = local_idx;
                } else if (prev_idx == uint.max) {
                    prev_idx = local_idx;
                } else {
                    *next_index() = first_idx;
                    *next_index() = prev_idx;
                    *next_index() = local_idx;
                    prev_idx = local_idx;
                }
            }
            break;
        }

        case GXFifoCommand.DrawTriangleStrip: {
            uint prev0 = uint.max;
            uint prev1 = uint.max;
            for (int i = 0; i < number_of_expected_vertices; i++) {
                Vertex v = decode_vertex();
                uint local_idx = cast(uint) (opengl_renderer.get_current_vertex_offset() - accumulated_geometry.shared_vertex_start);
                *next_vertex() = v;

                if (prev0 == uint.max) {
                    prev0 = local_idx;
                } else if (prev1 == uint.max) {
                    prev1 = local_idx;
                } else {
                    *next_index() = prev0;
                    *next_index() = prev1;
                    *next_index() = local_idx;
                    prev0 = prev1;
                    prev1 = local_idx;
                }
            }
            break;
        }

        case GXFifoCommand.DrawLines:
            for (int i = 0; i < number_of_expected_vertices; i++) {
                Vertex v = decode_vertex();
                *next_vertex() = v;
            }
            break;

        default:
            error_hollywood("Unimplemented draw command: %s", current_draw_command);
        }

        accumulated_geometry.shared_index_count  = opengl_renderer.get_current_index_offset()  - accumulated_geometry.shared_index_start;
        accumulated_geometry.shared_vertex_count = opengl_renderer.get_current_vertex_offset() - accumulated_geometry.shared_vertex_start;

        if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
            flush_accumulated_batch();
        }
    }

    public void render_xfb() {
        opengl_renderer.render_xfb();
    }

    private uint gc_blend_factor_to_gl(int gc_factor) {
        final switch (gc_factor) {
            case 0: return GL_ZERO;
            case 1: return GL_ONE;
            case 2: return GL_SRC_COLOR;
            case 3: return GL_ONE_MINUS_SRC_COLOR;
            case 4: return GL_SRC_ALPHA;
            case 5: return GL_ONE_MINUS_SRC_ALPHA;
            case 6: return GL_DST_ALPHA;
            case 7: return GL_ONE_MINUS_DST_ALPHA;
        }
    }

    void draw_shape_groups(ShapeGroup[] shape_groups) {
        if (shape_groups.length == 0) {
            return;
        }

        glUseProgram(gl_program);
        glClearColor(
            blitting_processor.get_copy_clear_color_red() / 255.0f,
            blitting_processor.get_copy_clear_color_green() / 255.0f, 
            blitting_processor.get_copy_clear_color_blue() / 255.0f,
            blitting_processor.get_copy_clear_color_alpha() / 255.0f
        ); 
        glEnable(GL_DEPTH_TEST);
        glDepthMask(GL_TRUE);
        // glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        // glEnable(GL_BLEND);
        
        gl_object_manager.deallocate_all_objects();
        
        foreach (ShapeGroup shape_group; shape_groups) {
            draw_shape_group(shape_group);
        }

        this.shape_groups.reset();
    }

    void draw_shape_group(ShapeGroup shape_group) {
        apply_opengl_state(current_render_state);
        submit_geometry_to_opengl(shape_group, current_render_state);
    }

    void submit_geometry_to_opengl(ShapeGroup geometry, RenderState render_state) {
        log_hollywood("Submitting shape group to OpenGL (%d %d %d %d)", geometry.shared_vertex_count, geometry.shared_vertex_start, geometry.shared_index_count, geometry.shared_index_start);

        uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
        glBindVertexArray(vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, persistent_vertex_buffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, persistent_index_buffer);

        size_t base_offset = geometry.shared_vertex_start * Vertex.sizeof;
        
        glEnableVertexAttribArray(position_attr_location);
        glVertexAttribPointer(position_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 0));

        glEnableVertexAttribArray(normal_attr_location);
        glVertexAttribPointer(normal_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 3 * float.sizeof));

        glEnableVertexAttribArray(texcoord_attr_location);
        glVertexAttribPointer(texcoord_attr_location, 2, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 6 * float.sizeof));

        glEnableVertexAttribArray(color_attr_location);
        glVertexAttribPointer(color_attr_location, 4, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 22 * float.sizeof));

        glEnableVertexAttribArray(matrix_index_attr_location);
        glVertexAttribIPointer(matrix_index_attr_location, 1, GL_INT, Vertex.sizeof, cast(void*) (base_offset + 30 * float.sizeof));
            
        if (render_state.uses_per_vertex_matrices) {
            glUniform1fv(matrix_data_uniform_location, 256, general_matrix_ram.ptr);
        } else {
            glUniformMatrix4x3fv(position_matrix_uniform_location, 1, GL_TRUE, render_state.position_matrix.ptr);
        }

        glUniformMatrix4x3fv(texture_matrix_uniform_location,  1, GL_TRUE,  render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv  (mvp_uniform_location,             1, GL_FALSE, render_state.projection_matrix.ptr);

        glUniformBlockBinding(gl_program, tev_config_block_index, 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_tev_buffer);

        glUniformBlockBinding(gl_program, vertex_config_block_index, 1);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_vertex_config_buffer);

        glDrawElements(GL_TRIANGLES, cast(int) geometry.shared_index_count, GL_UNSIGNED_INT,
                       cast(void*) (geometry.shared_index_start * uint.sizeof));

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

        position_attr_location            = glGetAttribLocation(gl_program, "in_Position");
        normal_attr_location              = glGetAttribLocation(gl_program, "normal");
        texcoord_attr_location            = glGetAttribLocation(gl_program, "texcoord");
        color_attr_location               = glGetAttribLocation(gl_program, "in_color");
        matrix_index_attr_location        = glGetAttribLocation(gl_program, "matrix_index");
        position_matrix_uniform_location  = glGetUniformLocation(gl_program, "position_matrix");
        texture_matrix_uniform_location   = glGetUniformLocation(gl_program, "texture_matrix");
        matrix_data_uniform_location      = glGetUniformLocation(gl_program, "matrix_data");
        mvp_uniform_location              = glGetUniformLocation(gl_program, "MVP");
        tev_config_block_index            = glGetUniformBlockIndex(gl_program, "TevConfig");
        vertex_config_block_index         = glGetUniformBlockIndex(gl_program, "VertexConfig");

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

        if (target_byte == 3) {
            fifo_wrapped = value.bit(5);
        }
    }

    // todo: debugging that i will probably never reinstate
    ShapeGroup[] debug_get_drawn_shape_groups() {
        return [];
    }

    void debug_draw_shape_group(ShapeGroup shape_group) {

    }

    void debug_redraw(ShapeGroup[] shape_groups) {

    }

    void on_error() {
        import std.stdio;
        
        foreach (debug_value; fifo_debug_history.get()) {
            writefln("FIFO_DEBUG: (%016x %s)", debug_value.value, debug_value.state);
        }
    }
}

