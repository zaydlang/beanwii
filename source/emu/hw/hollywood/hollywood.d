module emu.hw.hollywood.hollywood;

import bindbc.opengl;
import emu.hw.cp.cp;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.gxfifo_ringbuffer;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.opengl.opengl_renderer;
import emu.hw.hollywood.texture;
import emu.hw.hollywood.vertexdecoder.decoder;
import emu.hw.hollywood.vertexdecoder.types;
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
    int next_bp_mask = 0x00ff_ffff;
    u32[256] bp_registers;

    ProjectionMode projection_mode;

    private State state;
    private size_t cached_bytes_needed = 1;
    
    private u32 xfb_addr;
    private u32 xfb_stride;
    private u8 tex_copy_format;
    private u8 cp_register;

    private u16 xf_register;
    private u16 xf_data_remaining;

    private GXFifoCommand current_draw_command;
    private int number_of_expected_bytes_for_shape;
    private int number_of_received_bytes_for_shape;
    
    private int bazinga;

    private GLfloat[6]  projection_matrix_parameters;

    bool general_matrix_dirty = true;
    private float[256] general_matrix_ram;
    bool normal_matrix_dirty = true;
    private float[256] normal_matrix_ram;
    bool dt_texture_matrix_dirty = true;
    private float[256] dt_texture_matrix_ram;

    private u32[4] load_mtx_idx_values;
    private int current_load_mtx_idx;

    private GlObjectManager gl_object_manager;
    private TextureManager texture_manager;
    
    private bool xfb_has_data = false;
    
    private u8[640 * 528 * 4] rgba_buffer;
    private u8[640 * 528 * 4] converted_buffer;
    
    private float[6] viewport;
    
    private u32 display_list_address;
    private u32 display_list_size;
    
    private OpenGLRenderer opengl_renderer;
    VertexDecodeState vertex_decode_state;
    VertexDecoder vertex_decoder;

    private int num_texgens;

    GLint uniform_buffer_alignment;
    
    auto next_vertex() {
        return opengl_renderer.next_vertex();
    }

    auto next_index() {
        return opengl_renderer.next_index();
    }
    
    ref OpenGLRenderer get_opengl_renderer() {
        return opengl_renderer;
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
        vertex_decoder = new VertexDecoder();
    }

    void init_opengl() {
        gl_object_manager = new GlObjectManager();
        texture_manager = new TextureManager();
        state = State.WaitingForCommand;

        opengl_renderer = new OpenGLRenderer(gl_object_manager);
        opengl_renderer.init_opengl();
    }

    private void submit_shape_group(ShapeGroup geometry) {
        opengl_renderer.submit_shape_group(geometry);
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
        opengl_renderer.flush_accumulated_batch();

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
        u16 src_x = opengl_renderer.get_efb_src_x();
        u16 src_y = opengl_renderer.get_efb_src_y();
        u16 width = opengl_renderer.get_efb_src_w();
        u16 height = opengl_renderer.get_efb_src_h();
        u32 dest_addr = xfb_addr;
        
        GLuint result_texture = opengl_renderer.copy_efb_to_texture(tex_copy_format, mipmap);
        
        texture_manager.invalidate_texture_at_address(dest_addr);
        texture_manager.cache_gpu_texture(dest_addr, result_texture);
        
        // Skip CPU-based processing since we're keeping texture on GPU
        
        return;

        if (mipmap) {
            downsample_rgba_buffer_by_2(rgba_buffer.ptr, width, height);
            width /= 2;
            height /= 2;
        }

        flip_image_vertically(rgba_buffer.ptr, width, height);
        
        u8 dest_format = tex_copy_format;

        switch (dest_format) {
            case 0x2:
                write_ia4_tiled(rgba_buffer.ptr, dest_addr, width, height);
                break;
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

    void flip_image_vertically(u8* buffer, u16 width, u16 height) {
        for (int y = 0; y < height / 2; y++) {
            for (int x = 0; x < width; x++) {
                int top_offset = (y * width + x) * 4;
                int bottom_offset = ((height - 1 - y) * width + x) * 4;
                
                for (int i = 0; i < 4; i++) {
                    u8 temp = buffer[top_offset + i];
                    buffer[top_offset + i] = buffer[bottom_offset + i];
                    buffer[bottom_offset + i] = temp;
                }
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

    void write_ia4_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 8);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 8; fine_x++) {
                auto x = tile_x * 8 + fine_x;
                auto y = tile_y * 4 + fine_y;

                current_address += 1;

                if (x >= width || y >= height) {
                    continue;
                }

                u8 intensity = (src[(y * width + x) * 4 + 0] + src[(y * width + x) * 4 + 1] + src[(y * width + x) * 4 + 2]) / 3;
                u8 alpha = src[(y * width + x) * 4 + 3];

                intensity >>= 4;
                alpha >>= 4;

                mem.physical_write_u8(current_address, cast(u8) (intensity | (alpha << 4)));
            }
            }
        }
        }
    }
    
    void write_rgba32_tiled(ubyte* src, u32 dest_addr, u16 width, u16 height) {
        int tiles_x = div_roundup(cast(int) width, 4);
        int tiles_y = div_roundup(cast(int) height, 4);
        
        u32 current_address = dest_addr;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            u32 ba_address = current_address;
            u32 rg_address = current_address + 32;
            
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
                    
                    mem.physical_write_u8(rg_address + 1, r);
                    mem.physical_write_u8(rg_address + 0, g);
                    mem.physical_write_u8(ba_address + 1, b);
                    mem.physical_write_u8(ba_address + 0, a);
                }
                
                ba_address += 2;
                rg_address += 2;
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
                    
                    mem.physical_write_u8(current_address + 0, cast(u8) (pixel >> 8));
                    mem.physical_write_u8(current_address + 1, cast(u8) (pixel & 0xFF));
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
        if (general_matrix_dirty || dt_texture_matrix_dirty) {
            for (int i = 0; i < num_texgens; i++) {
                int tex_slot = opengl_renderer.get_texture_descriptor(i).tex_matrix_slot;
                int dualtex_slot = opengl_renderer.get_texture_descriptor(i).dualtex_matrix_slot;

                float[12] tex_matrix;
                float[12] dualtex_matrix;

                for (int j = 0; j < 12; j++) {
                    tex_matrix[j] = general_matrix_ram[tex_slot * 4 + j];
                    dualtex_matrix[j] = dt_texture_matrix_ram[dualtex_slot * 4 + j];
                }

                opengl_renderer.set_tex_config_tex_matrix(i, tex_matrix);
                opengl_renderer.set_tex_config_dualtex_matrix(i, dualtex_matrix);
            }
        }

        if (general_matrix_dirty) {
            int matrix_idx = opengl_renderer.get_geometry_matrix_idx();
            float[12] new_matrix = general_matrix_ram[matrix_idx * 4 .. matrix_idx * 4 + 12];
            opengl_renderer.set_position_matrix(new_matrix);
        }

        if (normal_matrix_dirty) {
            int matrix_idx = opengl_renderer.get_geometry_matrix_idx();
            float[12] new_normal_matrix = normal_matrix_ram[matrix_idx * 4 .. matrix_idx * 4 + 12];
            opengl_renderer.set_normal_matrix(new_normal_matrix);
        }

        if (the_men_we_see != the_men_you_see) {
            writefln("?????????????? mismatch between the men we see and the men you see");
        }

        general_matrix_dirty = false;
        normal_matrix_dirty = false;
        dt_texture_matrix_dirty = false;
    }
    
    public GLuint get_xfb_texture() {
        return opengl_renderer.get_xfb_color_texture();
    }
    
    public bool has_xfb_data() {
        return xfb_has_data;
    }

    Mem mem;
    void connect_mem(Mem mem) {
        // todo: bad
        this.mem = mem;
        this.vertex_decode_state.mem = mem;
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
                            opengl_renderer.gl_debug_marker("load_mtx_idx(%d, size=%d, address=0x%03x, mtxidx=%d)", current_load_mtx_idx, size, address, mtxidx);

                            u32 src_addr = 
                                 vertex_decode_state.array_bases[12 + current_load_mtx_idx] + 
                                (vertex_decode_state.array_strides[12 + current_load_mtx_idx] * mtxidx);

                            for (int i = 0; i < size; i++) {
                                u32 float_bits = mem.physical_read_u32(src_addr + i * 4);
                                
                                // writefln("GRIGOR: %x %x %x %x %d %f\n", 
                                // 12 + current_load_mtx_idx, mtxidx, address, size, i, 
                                // force_cast!float(float_bits));

                                // TODO: fixme
                                if (address + i <= 0xff) {
                                    general_matrix_dirty = true;
                                    general_matrix_ram[address + i] = force_cast!float(float_bits);
                                } else if (address + i >= 0x400 && address + i <= 0x4ff) {
                                    normal_matrix_dirty = true;
                                    normal_matrix_ram[address + i - 0x400] = force_cast!float(float_bits);
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
                        vertex_decode_state.number_of_expected_vertices = data_value;
                        vertex_decode_state.bytes_per_vertex = size_of_incoming_vertex(vertex_decode_state.current_vat);
                        number_of_expected_bytes_for_shape = vertex_decode_state.bytes_per_vertex * vertex_decode_state.number_of_expected_vertices;
                        state = State.WaitingForVertexData;
                        cached_bytes_needed = number_of_expected_bytes_for_shape;
                        log_hollywood("vat: %s", vertex_decode_state.vats[vertex_decode_state.current_vat]);
                        log_hollywood("vcd: %s", vertex_decode_state.vertex_descriptors[0]);
                        log_hollywood("Number of vertices: %d", vertex_decode_state.number_of_expected_vertices);
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
                vertex_decode_state.current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vertex_decode_state.vats[vertex_decode_state.current_vat]);
                log_hollywood("vcd: %s", vertex_decode_state.vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawTriangles | 0: .. case GXFifoCommand.DrawTriangles | 7:
                current_draw_command = GXFifoCommand.DrawTriangles;
                vertex_decode_state.current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vertex_decode_state.vats[vertex_decode_state.current_vat]);
                log_hollywood("vcd: %s", vertex_decode_state.vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawTriangleFan | 0: .. case GXFifoCommand.DrawTriangleFan | 7:
                current_draw_command = GXFifoCommand.DrawTriangleFan;
                vertex_decode_state.current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vertex_decode_state.vats[vertex_decode_state.current_vat]);
                log_hollywood("vcd: %s", vertex_decode_state.vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawTriangleStrip | 0: .. case GXFifoCommand.DrawTriangleStrip | 7:
                current_draw_command = GXFifoCommand.DrawTriangleStrip;
                vertex_decode_state.current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vertex_decode_state.vats[vertex_decode_state.current_vat]);
                log_hollywood("vcd: %s", vertex_decode_state.vertex_descriptors[0]);

                state = State.WaitingForNumberOfVertices;
                cached_bytes_needed = 2;
                break;
            
            case GXFifoCommand.DrawLines | 0: .. case GXFifoCommand.DrawLines | 7:
                current_draw_command = GXFifoCommand.DrawLines;
                vertex_decode_state.current_vat = (cast(int) command).bits(0, 2);
                log_hollywood("vat: %s", vertex_decode_state.vats[vertex_decode_state.current_vat]);
                log_hollywood("vcd: %s", vertex_decode_state.vertex_descriptors[0]);

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
                opengl_renderer.set_depth_test_enabled(bp_data.bit(0));
                opengl_renderer.set_depth_write_enabled(bp_data.bit(4));

                final switch (bp_data.bits(1, 3)) {
                    case 0: opengl_renderer.set_depth_func(GL_NEVER); break;
                    case 1: opengl_renderer.set_depth_func(GL_LESS); break;
                    case 2: opengl_renderer.set_depth_func(GL_EQUAL); break;
                    case 3: opengl_renderer.set_depth_func(GL_LEQUAL); break;
                    case 4: opengl_renderer.set_depth_func(GL_GREATER); break;
                    case 5: opengl_renderer.set_depth_func(GL_NOTEQUAL); break;
                    case 6: opengl_renderer.set_depth_func(GL_GEQUAL); break;
                    case 7: opengl_renderer.set_depth_func(GL_ALWAYS); break;
                }

                break;
            
            case 0x41:
                opengl_renderer.set_logicop_enable(bp_data.bit(1));
                opengl_renderer.set_color_update_enable(bp_data.bit(3));
                opengl_renderer.set_alpha_update_enable(bp_data.bit(4));
                opengl_renderer.set_arithmetic_blending_enable(bp_data.bit(0));
                opengl_renderer.set_blend_destination(cast(int) bp_data.bits(5, 7));
                opengl_renderer.set_blend_source(cast(int) bp_data.bits(8, 10));
                opengl_renderer.set_subtractive_additive_toggle(bp_data.bit(11));
                opengl_renderer.set_logicop(bp_data.bits(12, 15));
                break;
            
            case 0x42:
                opengl_renderer.set_is_alpha_forced(bp_data.bit(8));
                opengl_renderer.set_forced_alpha(bp_data.bits(0, 7));
                break;

            case 0x49:
                opengl_renderer.set_efb_src_x(cast(u16) bp_data.bits(0, 9));
                opengl_renderer.set_efb_src_y(cast(u16) bp_data.bits(10, 21));
                break;
            
            case 0x4a:
                opengl_renderer.set_efb_src_w(cast(u16) (bp_data.bits(0, 9) + 1));
                opengl_renderer.set_efb_src_h(cast(u16) (bp_data.bits(10, 21) + 1));
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
                opengl_renderer.set_clear_color_alpha(cast(u8) bp_data.bits(8, 15));
                opengl_renderer.set_clear_color_red(cast(u8) bp_data.bits(0, 7));
                break;

            case 0x50:
                opengl_renderer.set_clear_color_green(cast(u8) bp_data.bits(8, 15));
                opengl_renderer.set_clear_color_blue(cast(u8) bp_data.bits(0, 7));
                break;
                
            case 0x51:
                opengl_renderer.set_clear_depth(bp_data);
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
                opengl_renderer.set_scissor_top(bp_data.bits(0, 11) - 342);
                opengl_renderer.set_scissor_left(bp_data.bits(12, 23) - 342);
                break;
            
            case 0x21:
                opengl_renderer.set_scissor_bottom(bp_data.bits(0, 11) - 342 + 1);
                opengl_renderer.set_scissor_right(bp_data.bits(12, 23) - 342 + 1);
                break;

            case 0x59:
                opengl_renderer.set_scissorbox_offset_x(bp_data.bits(0, 9) * 2 - 342);
                opengl_renderer.set_scissorbox_offset_y(bp_data.bits(10, 19) * 2 - 342);
                break;
            
            case 0x00:
                opengl_renderer.set_tev_num_stages(bp_data.bits(10, 13) + 1);
                opengl_renderer.set_cull_mode(bp_data.bits(14, 15));
                log_hollywood("GEN_MODE: %08x", bp_data);
                break;

            case 0x94: .. case 0x97:
                opengl_renderer.set_texture_descriptor_base_address(bp_register - 0x94, bp_data << 5);
                break;
            
            case 0xb4: .. case 0xb7:
                opengl_renderer.set_texture_descriptor_base_address(bp_register - 0xb4 + 4, bp_data << 5);
                break;
            
            case 0x88: .. case 0x8b:
                opengl_renderer.set_texture_descriptor_width(bp_register - 0x88, bp_data.bits(0, 9) + 1);
                opengl_renderer.set_texture_descriptor_height(bp_register - 0x88, bp_data.bits(10, 19) + 1);
                opengl_renderer.set_texture_descriptor_type(bp_register - 0x88, cast(TextureType) bp_data.bits(20, 23));
                break;
            
            case 0xa8: .. case 0xab:
                opengl_renderer.set_texture_descriptor_width(bp_register - 0xa8 + 4, bp_data.bits(0, 9) + 1);
                opengl_renderer.set_texture_descriptor_height(bp_register - 0xa8 + 4, bp_data.bits(10, 19) + 1);
                opengl_renderer.set_texture_descriptor_type(bp_register - 0xa8 + 4, cast(TextureType) bp_data.bits(20, 23));
                break;

            case 0x10: .. case 0x1f:
                break;
            
            case 0x28: .. case 0x2f:
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
                if (bp_register.bit(0)) {
                    log_hollywood("TEV_ALPHA_ENV_%x: %08x (tev op 1) at pc 0x%08x", bp_register - 0xc1, bp_data, mem.cpu.state.pc);
                    int idx = (bp_register - 0xc1) / 2;
                    
                    u32 bias = bp_data.bits(16, 17);
                    u32 scale = bp_data.bits(20, 21);
                    opengl_renderer.set_tev_stage_in_alfa_a(idx, bp_data.bits(13, 15));
                    opengl_renderer.set_tev_stage_in_alfa_b(idx, bp_data.bits(10, 12));
                    opengl_renderer.set_tev_stage_in_alfa_c(idx, bp_data.bits(7, 9));
                    opengl_renderer.set_tev_stage_in_alfa_d(idx, bp_data.bits(4, 6));

                    if (bias == 3) {
                        opengl_renderer.set_tev_stage_alfa_op(idx, 0x8 | (bp_data.bit(18)) | (scale << 1));
                    } else {
                        opengl_renderer.set_tev_stage_alfa_op(idx, bp_data.bit(18));
                    }

                    opengl_renderer.set_tev_stage_bias_alfa(idx,
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5);
                    opengl_renderer.set_tev_stage_alfa_dest(idx, bp_data.bits(22, 23));
                    opengl_renderer.set_tev_stage_clamp_alfa(idx, bp_data.bit(19));

                    opengl_renderer.set_tev_stage_scale_alfa(idx,
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5);

                    log_hollywood("Set indices to %d %d", bp_data.bits(0, 1), bp_data.bits(2, 3));
                    opengl_renderer.set_tev_stage_ras_swap_table_index(idx, bp_data.bits(0, 1));
                    opengl_renderer.set_tev_stage_tex_swap_table_index(idx, bp_data.bits(2, 3));
                    break;
                } else {
                    int idx = (bp_register - 0xc0) / 2;

                    u32 bias = bp_data.bits(16, 17);
                    u32 scale = bp_data.bits(20, 21);
                    opengl_renderer.set_tev_stage_in_color_a(idx, bp_data.bits(12, 15));
                    opengl_renderer.set_tev_stage_in_color_b(idx, bp_data.bits(8, 11));
                    opengl_renderer.set_tev_stage_in_color_c(idx, bp_data.bits(4, 7));
                    opengl_renderer.set_tev_stage_in_color_d(idx, bp_data.bits(0, 3));

                    if (bias == 3) {
                        opengl_renderer.set_tev_stage_color_op(idx, 0x8 | (bp_data.bit(18)) | (scale << 1));
                    } else {
                        opengl_renderer.set_tev_stage_color_op(idx, bp_data.bit(18));
                    }

                    opengl_renderer.set_tev_stage_bias_color(idx,
                        bp_data.bits(16, 17) == 0 ? 0 :
                        bp_data.bits(16, 17) == 1 ? 0.5 :
                        -0.5);
                    opengl_renderer.set_tev_stage_clamp_color(idx, bp_data.bit(19));
                    opengl_renderer.set_tev_stage_color_dest(idx, bp_data.bits(22, 23));

                    opengl_renderer.set_tev_stage_scale_color(idx,
                        bp_data.bits(20, 21) == 0 ? 1 :
                        bp_data.bits(20, 21) == 1 ? 2 :
                        bp_data.bits(20, 21) == 2 ? 4 :
                        0.5);
                }
                break;
            
            case 0xe0: .. case 0xe7:
                if (bp_data.bit(23)) {
                    int idx = (bp_register - 0xe0) / 2;
                    if (bp_register.bit(0)) {
                        final switch (idx) {
                        case 0: 
                            opengl_renderer.set_tev_k(0, 2, bp_data.bits(0, 7) / 255.0f); 
                            opengl_renderer.set_tev_k(0, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 1:
                            opengl_renderer.set_tev_k(1, 2, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_k(1, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 2:
                            opengl_renderer.set_tev_k(2, 2, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_k(2, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 3:
                            opengl_renderer.set_tev_k(3, 2, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_k(3, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        }
                    } else {
                        final switch (idx) {
                        case 0: 
                            opengl_renderer.set_tev_k(0, 0, bp_data.bits(0, 7) / 255.0f); 
                            opengl_renderer.set_tev_k(0, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 1:
                            opengl_renderer.set_tev_k(1, 0, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_k(1, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 2:
                            opengl_renderer.set_tev_k(2, 0, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_k(2, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 3:
                            opengl_renderer.set_tev_k(3, 0, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_k(3, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        }
                    }
                } else {
                    if (bp_register.bit(0)) {
                        int idx = (bp_register - 0xe1) / 2;
                        // i dont trust D's memory layout
                        final switch (idx) {
                        case 0: 
                            opengl_renderer.set_tev_reg(0, 2, bp_data.bits(0, 7) / 255.0f); 
                            opengl_renderer.set_tev_reg(0, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 1:
                            opengl_renderer.set_tev_reg(1, 2, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_reg(1, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 2:
                            opengl_renderer.set_tev_reg(2, 2, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_reg(2, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 3:
                            opengl_renderer.set_tev_reg(3, 2, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_reg(3, 1, bp_data.bits(12, 19) / 255.0f);
                            break;
                        }
                    } else {
                        int idx = (bp_register - 0xe0) / 2;
                        // i dont trust D's memory layout
                        final switch (idx) {
                        case 0: 
                            opengl_renderer.set_tev_reg(0, 0, bp_data.bits(0, 7) / 255.0f); 
                            opengl_renderer.set_tev_reg(0, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 1:
                            opengl_renderer.set_tev_reg(1, 0, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_reg(1, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 2:
                            opengl_renderer.set_tev_reg(2, 0, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_reg(2, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        case 3:
                            opengl_renderer.set_tev_reg(3, 0, bp_data.bits(0, 7) / 255.0f);
                            opengl_renderer.set_tev_reg(3, 3, bp_data.bits(12, 19) / 255.0f);
                            break;
                        }
                    }
                }
                break;
       
            case 0xee: .. case 0xf1:
                log_hollywood("TEV_FOG_PARAM_%x: %08x", bp_register - 0xee, bp_data);
                break;

            case 0xf3:
                opengl_renderer.set_alpha_comp0(cast(u8) bp_data.bits(16, 18));
                opengl_renderer.set_alpha_comp1(cast(u8) bp_data.bits(19, 21));
                opengl_renderer.set_alpha_aop(cast(u8) bp_data.bits(22, 23));
                opengl_renderer.set_alpha_ref0(cast(u8) bp_data.bits(0, 7));
                opengl_renderer.set_alpha_ref1(cast(u8) bp_data.bits(8, 15));
                opengl_renderer.set_tev_alpha_comp0(opengl_renderer.get_alpha_comp0());
                opengl_renderer.set_tev_alpha_comp1(opengl_renderer.get_alpha_comp1());
                opengl_renderer.set_tev_alpha_aop(opengl_renderer.get_alpha_aop());
                opengl_renderer.set_tev_alpha_ref0(opengl_renderer.get_alpha_ref0());
                opengl_renderer.set_tev_alpha_ref1(opengl_renderer.get_alpha_ref1());
                break;
            
            case 0xf4: .. case 0xf5:
                log_hollywood("TEV_Z_ENV_%x: %08x", bp_register - 0xf4, bp_data);
                break;

            case 0x80: .. case 0x83:
                opengl_renderer.set_texture_descriptor_wrap_s(bp_register - 0x80, cast(TextureWrap) bp_data.bits(0, 1));
                opengl_renderer.set_texture_descriptor_wrap_t(bp_register - 0x80, cast(TextureWrap) bp_data.bits(2, 3));
                break;

            case 0xa0: .. case 0xa3:
                opengl_renderer.set_texture_descriptor_wrap_s(bp_register - 0xa0 + 4, cast(TextureWrap) bp_data.bits(0, 1));
                opengl_renderer.set_texture_descriptor_wrap_t(bp_register - 0xa0 + 4, cast(TextureWrap) bp_data.bits(2, 3));
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
                log_texture("TEV_SWAP_MODE_TABLE_%02x: %08x", bp_register, bp_data);
                int idx = (bp_register - 0xf6) / 2;
                u64 current_swap = opengl_renderer.get_tev_config().swap_tables;
                current_swap &= ~(0xf << (idx * 8));
                current_swap |= value.bits(0, 3) << (idx * 8);
                opengl_renderer.set_tev_swap_tables(current_swap);
                opengl_renderer.set_tev_stage_kcsel(idx * 4 + 0, value.bits(4, 8));
                opengl_renderer.set_tev_stage_kasel(idx * 4 + 0, value.bits(9, 13));
                opengl_renderer.set_tev_stage_kcsel(idx * 4 + 1, value.bits(14, 18));
                opengl_renderer.set_tev_stage_kasel(idx * 4 + 1, value.bits(19, 23));
                assert_texture(opengl_renderer.get_tev_config().stages[idx * 4 + 0].kasel != 12, "Invalid kcsel");
                assert_texture(opengl_renderer.get_tev_config().stages[idx * 4 + 1].kasel != 12, "Invalid kcsel");
                break;

            case 0xf7:
            case 0xf9:
            case 0xfb:
            case 0xfd:
                log_texture("TEV_SWAP_MODE_TABLE_%02x: %08x", bp_register, bp_data);
                int idx = (bp_register - 0xf6) / 2;
                u64 current_swap2 = opengl_renderer.get_tev_config().swap_tables;
                current_swap2 &= ~(0xf << (idx * 8 + 4));
                current_swap2 |= bp_data.bits(0, 3) << (idx * 8 + 4);
                opengl_renderer.set_tev_swap_tables(current_swap2);
                opengl_renderer.set_tev_stage_kcsel(idx * 4 + 2, bp_data.bits(4, 8));
                opengl_renderer.set_tev_stage_kasel(idx * 4 + 2, bp_data.bits(9, 13));
                opengl_renderer.set_tev_stage_kcsel(idx * 4 + 3, bp_data.bits(14, 18));
                opengl_renderer.set_tev_stage_kasel(idx * 4 + 3, bp_data.bits(19, 23));
                assert_texture(opengl_renderer.get_tev_config().stages[idx * 4 + 2].kasel != 12, "Invalid kcsel");
                assert_texture(opengl_renderer.get_tev_config().stages[idx * 4 + 3].kasel != 12, "Invalid kcsel");
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
                general_matrix_dirty = true;
                opengl_renderer.set_geometry_matrix_idx(value.bits(0, 5));
                the_men_you_see = value.bits(0, 5);
                break;

            case 0x50: .. case 0x57:
                auto vcd = &vertex_decode_state.vertex_descriptors[register - 0x50];
                vcd.raw_vcd_lo = value;

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
                
                opengl_renderer.set_uses_per_vertex_matrices((vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent));

                break;
            
            case 0x60: .. case 0x67:
                auto vcd = &vertex_decode_state.vertex_descriptors[register - 0x60];
                vcd.raw_vcd_hi = value;

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
                auto vat = &vertex_decode_state.vats[register - 0x70];
                vat.raw_vat_a = value;

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
                auto vat = &vertex_decode_state.vats[register - 0x80];
                vat.raw_vat_b = value;
                
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
                auto vat = &vertex_decode_state.vats[register - 0x90];
                vat.raw_vat_c = value;
                
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
                vertex_decode_state.array_bases[register - 0xa0] = value;
                break;

            case 0xb0: .. case 0xbf:
                vertex_decode_state.array_strides[register - 0xb0] = value;
                break;

            default:
                log_hollywood("Unimplemented: CP register %02x", register);
                break;
        }
    }

    private int size_of_incoming_vertex(int vat_idx) {
        auto vcd = &vertex_decode_state.vertex_descriptors[0];
        auto vat = &vertex_decode_state.vats[vat_idx];

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

    int the_men_we_see; 
    int the_men_you_see; 
    private void handle_new_transform_unit_write(u16 register, u32 value) {
        switch (register) {
            case 0x1018:
                log_hollywood("geometry_matrix: %08x", value);
                general_matrix_dirty = true;
                the_men_we_see = value.bits(0, 5);
                opengl_renderer.set_geometry_matrix_idx(value.bits(0, 5));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(0, value.bits(6, 11));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(1, value.bits(12, 17));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(2, value.bits(18, 23));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(3, value.bits(24, 29));
                break;

            case 0x1019:
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(4, value.bits(0, 5));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(5, value.bits(6, 11));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(6, value.bits(12, 17));
                opengl_renderer.set_texture_descriptor_tex_matrix_slot(7, value.bits(18, 23));
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
                opengl_renderer.set_tex_config_texmatrix_size(idx, cast(u32)(value.bit(1) ? 3 : 2));
                opengl_renderer.set_tex_config_use_stq(idx, cast(u32)value.bit(2));
                opengl_renderer.set_tex_config_texcoord_source(idx, cast(u32)value.bits(7, 11));
                break;

            case 0x0000: .. case 0x00ff:
                opengl_renderer.gl_debug_marker("general_matrix_ram[%d] = %f", register, force_cast!float(value));

                general_matrix_dirty = true;
                general_matrix_ram[register] = force_cast!float(value);
                break;

            case 0x0400: .. case 0x04ff:
                normal_matrix_dirty = true;
                normal_matrix_ram[register - 0x400] = force_cast!float(value);
                break;
            
            case 0x0500: .. case 0x05ff:
                dt_texture_matrix_dirty = true;
                dt_texture_matrix_ram[register - 0x500] = force_cast!float(value);
                break;
            
            case 0x1050: .. case 0x1057:
                int idx = register - 0x1050;

                opengl_renderer.set_texture_descriptor_dualtex_matrix_slot(idx, value.bits(0, 5));
                opengl_renderer.set_tex_config_normalize_before_dualtex(idx, value.bit(8));
                break;
            
            case 0x100c:
                float[4] mat = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                vertex_decode_state.color_global[0] = mat;
                opengl_renderer.set_material_color(0, mat);
                break;
            
            case 0x100d:
                float[4] mat = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                vertex_decode_state.color_global[1] = mat;
                opengl_renderer.set_material_color(1, mat);
                break;

            case 0x100a: {
                float[4] amb0 = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                opengl_renderer.set_ambient_color(0, amb0);
                break;
            }

            case 0x100b: {
                float[4] amb1 = [
                    value.bits(24, 31) / 255.0,
                    value.bits(16, 23) / 255.0,
                    value.bits(8, 15) / 255.0,
                    value.bits(0, 7) / 255.0
                ];
                opengl_renderer.set_ambient_color(1, amb1);
                break;
            }
            
            case 0x100e: {
                ChannelControl ctrl;
                ctrl.enable = value.bit(1);
                ctrl.ambient_src = value.bit(6);
                ctrl.material_src = value.bit(0);
                ctrl.light_mask = value.bits(2, 5) | (value.bits(11, 14) << 4);
                ctrl.diffuse_fn = value.bits(7, 8);
                ctrl.attenuation_fn = value.bits(9, 10);

                opengl_renderer.set_color_channel_control(0, ctrl);
                break;
            }
            
            case 0x100f: {
                ChannelControl ctrl;
                ctrl.enable = value.bit(1);
                ctrl.ambient_src = value.bit(6);
                ctrl.material_src = value.bit(0);
                ctrl.light_mask = value.bits(2, 5) | (value.bits(11, 14) << 4);
                ctrl.diffuse_fn = value.bits(7, 8);
                ctrl.attenuation_fn = value.bits(9, 10);

                opengl_renderer.set_color_channel_control(1, ctrl);
                break;
            }

            case 0x1010: {
                ChannelControl ctrl;
                ctrl.enable = value.bit(1);
                ctrl.ambient_src = value.bit(6);
                ctrl.material_src = value.bit(0);
                ctrl.light_mask = value.bits(2, 5) | (value.bits(11, 14) << 4);
                ctrl.diffuse_fn = value.bits(7, 8);
                ctrl.attenuation_fn = value.bits(9, 10);

                opengl_renderer.set_alpha_channel_control(0, ctrl);
                break;
            }

            case 0x1011: {
                ChannelControl ctrl;
                ctrl.enable = value.bit(1);
                ctrl.ambient_src = value.bit(6);
                ctrl.material_src = value.bit(0);
                ctrl.light_mask = value.bits(2, 5) | (value.bits(11, 14) << 4);
                ctrl.diffuse_fn = value.bits(7, 8);
                ctrl.attenuation_fn = value.bits(9, 10);

                opengl_renderer.set_alpha_channel_control(1, ctrl);
                break;
            }
            
            case 0x0600: .. case 0x06ff: {
                int idx = (register - 0x0600) / 0x10;
                int off = (register - 0x0600) % 0x10;

                auto vc = opengl_renderer.get_vertex_config();
                auto light = vc.lights[idx];

                switch (off) {
                    case 3: {
                        light.color = [
                            value.bits(24, 31) / 255.0f,
                            value.bits(16, 23) / 255.0f,
                            value.bits(8, 15)  / 255.0f,
                            value.bits(0, 7)   / 255.0f
                        ];
                        break;
                    }
                    
                    case 4:  light.dist_atten[0] = force_cast!float(value); break;
                    case 5:  light.dist_atten[1] = force_cast!float(value); break;
                    case 6:  light.dist_atten[2] = force_cast!float(value); break;
                    case 7:  light.spec_atten[0] = force_cast!float(value); break;
                    case 8:  light.spec_atten[1] = force_cast!float(value); break;
                    case 9:  light.spec_atten[2] = force_cast!float(value); break;
                    case 10: light.position[0]   = force_cast!float(value); break;
                    case 11: light.position[1]   = force_cast!float(value); break;
                    case 12: light.position[2]   = force_cast!float(value); break;
                    case 13: light.direction[0]  = force_cast!float(value); break;
                    case 14: light.direction[1]  = force_cast!float(value); break;
                    case 15: light.direction[2]  = force_cast!float(value); break;
                    
                    default:
                        break;
                }

                light.position[3] = 1.0f;
                light.direction[3] = 0.0f;
                opengl_renderer.set_light(idx, light);
                break;
            }
            
            case 0x103f:
                num_texgens = cast(int) value.bits(0, 3);
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
                opengl_renderer.set_projection_matrix([
                    p[0], 0,    0,     0,
                    0,    p[2], 0,     0,
                    p[1], p[3], p[4], -1,
                    0,    0,    p[5],  0
                ]);
                break;
            
            case ProjectionMode.Orthographic:
                opengl_renderer.set_projection_matrix([
                    p[0], 0,    0,    0,
                    0,    p[2], 0,    0,
                    0,    0,    p[4], 0,
                    p[1], p[3], p[5], 1
                ]);
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
        u32 array_addr = vertex_decode_state.array_bases[array_num];
        u32 array_stride = vertex_decode_state.array_strides[array_num];
        u32 array_offset = array_addr + (array_stride * idx) + (offset * cast(int) size);

        final switch (size) {
        case 1: return mem.physical_read_u8(array_offset);
        case 2: return mem.physical_read_u16(array_offset);
        case 3: return mem.physical_read_u32(array_offset);
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

        int enabled_textures = 0;
        for (int i = 0; i < opengl_renderer.get_tev_num_stages(); i++) {
            if (opengl_renderer.get_tev_config().stages[i].texmap_enable) {
                enabled_textures |= 1 << opengl_renderer.get_tev_config().stages[i].texmap;
            }
        }
        
        for (int i = 0; i < opengl_renderer.get_tev_num_stages(); i++) {
            if (enabled_textures.bit(i)) {
                auto j = opengl_renderer.get_tev_config().stages[i].texmap;
                opengl_renderer.set_texture_id(j, texture_manager.load_texture(opengl_renderer.get_texture_descriptor(j), mem, gl_object_manager));
            }
        }

        opengl_renderer.set_enabled_textures_bitmap(enabled_textures);
        opengl_renderer.init_geometry_tracking();

        auto first_vertex_index = opengl_renderer.get_local_vertex_index();

        auto decode_target = opengl_renderer.next_vertices(vertex_decode_state.number_of_expected_vertices);
        auto decode_result = vertex_decoder.decode_vertices(data, data_length, vertex_decode_state, decode_target, vertex_decode_state.number_of_expected_vertices);

        auto current_vertex_index = first_vertex_index;

        switch (current_draw_command) {
        case GXFifoCommand.DrawQuads: {
            auto next_indices = opengl_renderer.next_indices(6 * decode_result.vertices_emitted / 4);
            
            for (int i = 0; i < decode_result.vertices_emitted / 4; i++) {
                *next_indices++ = current_vertex_index + 0;
                *next_indices++ = current_vertex_index + 1;
                *next_indices++ = current_vertex_index + 2;
                *next_indices++ = current_vertex_index + 0;
                *next_indices++ = current_vertex_index + 2;
                *next_indices++ = current_vertex_index + 3;
            
                current_vertex_index += 4;
            }

            break;
        }

        case GXFifoCommand.DrawTriangles: {
            auto next_indices = opengl_renderer.next_indices(decode_result.vertices_emitted);

            for (int i = 0; i < decode_result.vertices_emitted; i++) {
                *next_indices++ = current_vertex_index + i;
            }
            
            break;
        }

        case GXFifoCommand.DrawTriangleFan: {
            if (decode_result.vertices_emitted >= 3) {
                auto next_indices = opengl_renderer.next_indices(3 * (decode_result.vertices_emitted - 2));
                uint first_idx = current_vertex_index + 0;
                uint prev_idx = current_vertex_index + 1;

                for (int i = 2; i < decode_result.vertices_emitted; i++) {
                    uint local_idx = current_vertex_index + cast(uint) i;
                    *next_indices++ = first_idx;
                    *next_indices++ = prev_idx;
                    *next_indices++ = local_idx;
                    prev_idx = local_idx;
                }

                current_vertex_index += decode_result.vertices_emitted;
            }

            break;
        }

        case GXFifoCommand.DrawTriangleStrip: {
            if (decode_result.vertices_emitted >= 3) {
                auto next_indices = opengl_renderer.next_indices(3 * (decode_result.vertices_emitted - 2));
                uint prev0 = current_vertex_index + 0;
                uint prev1 = current_vertex_index + 1;

                for (int i = 2; i < decode_result.vertices_emitted; i++) {
                    uint local_idx = current_vertex_index + cast(uint) i;
                    *next_indices++ = prev0;
                    *next_indices++ = prev1;
                    *next_indices++ = local_idx;
                    prev0 = prev1;
                    prev1 = local_idx;
                }

                current_vertex_index += decode_result.vertices_emitted;
            }

            break;
        }

        case GXFifoCommand.DrawLines:
            // Vertices already decoded; indices unnecessary for lines in this path
            break;

        default:
            error_hollywood("Unimplemented draw command: %s", current_draw_command);
        }

        // if (opengl_renderer.get_uses_per_vertex_matrices()) {
            opengl_renderer.set_general_matrix_ram(general_matrix_ram);
            opengl_renderer.set_normal_matrix_ram(normal_matrix_ram);
        // }

        opengl_renderer.finalize_geometry();
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
