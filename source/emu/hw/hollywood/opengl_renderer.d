module emu.hw.hollywood.opengl_renderer;

import bindbc.opengl;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.texture;
import util.bitop;
import util.log;
import util.number;
import std.file;
import std.string;

final class OpenGLRenderer {
    private RenderState render_state;
    
    private GlObjectManager gl_object_manager;
    
    private GLuint gl_program;
    private int[8] texture_uniform_locations;
    private int position_attr_location = -1;
    private int normal_attr_location = -1;
    private int texcoord_attr_location = -1;
    private int color_attr_location = -1;
    private int matrix_index_attr_location = -1;
    private int position_matrix_uniform_location = -1;
    private int texture_matrix_uniform_location = -1;
    private int matrix_data_uniform_location = -1;
    private int mvp_uniform_location = -1;
    private uint tev_config_block_index = -1;
    private uint vertex_config_block_index = -1;
    private uint persistent_vertex_buffer = 0;
    private uint persistent_tev_buffer = 0;
    private uint persistent_vertex_config_buffer = 0;
    private uint persistent_index_buffer = 0;
    private float[256] general_matrix_ram;
    
    private GLuint efb_fbo;
    private GLuint efb_color_texture;
    private GLuint efb_depth_texture;
    private GLuint xfb_fbo;
    private GLuint xfb_color_texture;
    private GLuint xfb_shader_program;
    private GLuint xfb_vao;
    private GLuint xfb_vbo;
    
    private Vertex* persistent_vertex_ptr = null;
    private uint* persistent_index_ptr = null;
    
    static immutable size_t MAX_VERTICES = 1024 * 1024;
    static immutable size_t MAX_INDICES = MAX_VERTICES * 6;
    
    this(GlObjectManager gl_object_manager) {
        this.gl_object_manager = gl_object_manager;
        render_state = RenderState();
    }
    
    void init_opengl() {
        int uniform_buffer_alignment;
        glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, &uniform_buffer_alignment);

        glGenBuffers(1, &persistent_vertex_buffer);
        glBindBuffer(GL_ARRAY_BUFFER, persistent_vertex_buffer);
        glBufferStorage(GL_ARRAY_BUFFER, MAX_VERTICES * Vertex.sizeof, null, 
                       GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        persistent_vertex_ptr = cast(Vertex*) glMapBufferRange(GL_ARRAY_BUFFER, 0, MAX_VERTICES * Vertex.sizeof,
                                                              GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        
        glGenBuffers(1, &persistent_tev_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
        glBufferData(GL_UNIFORM_BUFFER, TevConfig.sizeof, null, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &persistent_vertex_config_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferData(GL_UNIFORM_BUFFER, VertexConfig.sizeof, null, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &persistent_index_buffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, persistent_index_buffer);
        glBufferStorage(GL_ELEMENT_ARRAY_BUFFER, MAX_INDICES * uint.sizeof, null,
                       GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        persistent_index_ptr = cast(uint*) glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, 0, MAX_INDICES * uint.sizeof,
                                                           GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);

        load_shaders();

        render_state.projection_matrix[15] = 1;
        
        glGenFramebuffers(1, &efb_fbo);
        glGenTextures(1, &efb_color_texture);
        glGenTextures(1, &efb_depth_texture);
        
        glBindTexture(GL_TEXTURE_2D, efb_color_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 528, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glBindTexture(GL_TEXTURE_2D, efb_depth_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, 640, 528, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, efb_color_texture, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, efb_depth_texture, 0);
        
        glGenFramebuffers(1, &xfb_fbo);
        glGenTextures(1, &xfb_color_texture);
        
        glBindTexture(GL_TEXTURE_2D, xfb_color_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 480, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glBindFramebuffer(GL_FRAMEBUFFER, xfb_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, xfb_color_texture, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        
        init_xfb_shader();
    }
    
    private void init_xfb_shader() {
        string xfb_vertex_text = readText("source/emu/hw/hollywood/shaders/xfb_vertex.glsl");
        string xfb_fragment_text = readText("source/emu/hw/hollywood/shaders/xfb_fragment.glsl");
        
        GLuint xfb_vertex_shader = glCreateShader(GL_VERTEX_SHADER);
        auto xfb_vertex_src_ptr = xfb_vertex_text.ptr;
        auto xfb_vertex_src_len = cast(int)xfb_vertex_text.length;
        glShaderSource(xfb_vertex_shader, 1, &xfb_vertex_src_ptr, &xfb_vertex_src_len);
        glCompileShader(xfb_vertex_shader);
        
        GLuint xfb_fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
        auto xfb_fragment_src_ptr = xfb_fragment_text.ptr;
        auto xfb_fragment_src_len = cast(int)xfb_fragment_text.length;
        glShaderSource(xfb_fragment_shader, 1, &xfb_fragment_src_ptr, &xfb_fragment_src_len);
        glCompileShader(xfb_fragment_shader);
        
        xfb_shader_program = glCreateProgram();
        glAttachShader(xfb_shader_program, xfb_vertex_shader);
        glAttachShader(xfb_shader_program, xfb_fragment_shader);
        glLinkProgram(xfb_shader_program);
        
        glDeleteShader(xfb_vertex_shader);
        glDeleteShader(xfb_fragment_shader);
        
        float[] xfb_quad_vertices = [
            -1.0f, -1.0f,  0.0f, 1.0f,
             1.0f, -1.0f,  1.0f, 1.0f,
             1.0f,  1.0f,  1.0f, 0.0f,
            -1.0f, -1.0f,  0.0f, 1.0f,
             1.0f,  1.0f,  1.0f, 0.0f,
            -1.0f,  1.0f,  0.0f, 0.0f
        ];
        
        glGenVertexArrays(1, &xfb_vao);
        glGenBuffers(1, &xfb_vbo);
        
        glBindVertexArray(xfb_vao);
        glBindBuffer(GL_ARRAY_BUFFER, xfb_vbo);
        glBufferData(GL_ARRAY_BUFFER, xfb_quad_vertices.length * float.sizeof, xfb_quad_vertices.ptr, GL_STATIC_DRAW);
        
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)0);
        glEnableVertexAttribArray(0);
        
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)(2 * float.sizeof));
        glEnableVertexAttribArray(1);
        
        glBindVertexArray(0);
    }
    
    private void load_shaders() {
        auto vertex_shader   = glCreateShader(GL_VERTEX_SHADER);
        auto fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);	
        string vertex_text   = readText("source/emu/hw/hollywood/shaders/vertex.glsl");
        string fragment_text = readText("source/emu/hw/hollywood/shaders/fragment.glsl");

        auto vertex_src_ptr = vertex_text.ptr;
        auto vertex_src_len = cast(int)vertex_text.length;
        glShaderSource(vertex_shader, 1, &vertex_src_ptr, &vertex_src_len);
        glCompileShader(vertex_shader);

        auto fragment_src_ptr = fragment_text.ptr;
        auto fragment_src_len = cast(int)fragment_text.length;
        glShaderSource(fragment_shader, 1, &fragment_src_ptr, &fragment_src_len);
        glCompileShader(fragment_shader);

        gl_program = glCreateProgram();
        glAttachShader(gl_program, vertex_shader);
        glAttachShader(gl_program, fragment_shader);
        glLinkProgram(gl_program);

        position_attr_location           = glGetAttribLocation(gl_program,  "in_Position");
        normal_attr_location             = glGetAttribLocation(gl_program,  "normal");
        texcoord_attr_location           = glGetAttribLocation(gl_program,  "texcoord");
        color_attr_location              = glGetAttribLocation(gl_program,  "in_color");
        matrix_index_attr_location       = glGetAttribLocation(gl_program,  "matrix_index");
        position_matrix_uniform_location = glGetUniformLocation(gl_program, "position_matrix");
        texture_matrix_uniform_location  = glGetUniformLocation(gl_program, "texture_matrix");
        matrix_data_uniform_location     = glGetUniformLocation(gl_program, "matrix_data");
        mvp_uniform_location             = glGetUniformLocation(gl_program, "MVP");
        tev_config_block_index           = glGetUniformBlockIndex(gl_program, "TevConfig");
        vertex_config_block_index        = glGetUniformBlockIndex(gl_program, "VertexConfig");

        for (int i = 0; i < 8; i++) {
            import std.string;
            auto texture_name = format("wiiscreen%d", i);
            texture_uniform_locations[i] = glGetUniformLocation(gl_program, texture_name.ptr);
        }

        glDeleteShader(vertex_shader);
        glDeleteShader(fragment_shader);
    }
    
    const(RenderState)* get_render_state() const {
        return &render_state;
    }
    
    RenderState* get_render_state_for_modification() {
        return &render_state;
    }
    
    void set_general_matrix_ram(float[256] matrix_ram) {
        general_matrix_ram = matrix_ram;
    }
    
    GLuint get_efb_fbo() const { return efb_fbo; }
    GLuint get_xfb_fbo() const { return xfb_fbo; }
    GLuint get_xfb_color_texture() const { return xfb_color_texture; }
    GLuint get_xfb_shader_program() const { return xfb_shader_program; }
    GLuint get_xfb_vao() const { return xfb_vao; }
    
    uint get_current_vertex_offset() const { return current_vertex_offset; }
    uint get_current_index_offset() const { return current_index_offset; }
    void set_current_vertex_offset(uint offset) { current_vertex_offset = offset; }
    void set_current_index_offset(uint offset) { current_index_offset = offset; }
    
    private uint current_vertex_offset = 0;
    private uint current_index_offset = 0;
    
    private bool xfb_has_data = false;
    
    Vertex* allocate_vertex() {
        if (current_vertex_offset >= MAX_VERTICES) {
            current_vertex_offset = 0;
        }
        
        return &persistent_vertex_ptr[current_vertex_offset++];
    }
    
    uint* allocate_index() {
        if (current_index_offset >= MAX_INDICES) {
            current_index_offset = 0;
        }
        
        return &persistent_index_ptr[current_index_offset++];
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
    
    void apply_opengl_state(RenderState render_state) {
        glUseProgram(gl_program);

        glClearColor(
            render_state.clear_color_red / 255.0f,
            render_state.clear_color_green / 255.0f,
            render_state.clear_color_blue / 255.0f,
            render_state.clear_color_alpha / 255.0f
        ); 
        
        gl_object_manager.deallocate_all_objects();
        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE, render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv(mvp_uniform_location, 1, GL_FALSE, render_state.projection_matrix.ptr);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);

        import std.stdio; writefln("num tev stages: %d", render_state.tev_config.num_tev_stages);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, TevConfig.sizeof, &render_state.tev_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_tev_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, VertexConfig.sizeof, &render_state.vertex_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_vertex_config_buffer);

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
        }
    }
    
    void submit_geometry_to_opengl(ShapeGroup geometry, RenderState render_state) {
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

        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE,  render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv  (mvp_uniform_location,            1, GL_FALSE, render_state.projection_matrix.ptr);
        glUniformBlockBinding(gl_program, tev_config_block_index, 1);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_tev_buffer);
        glUniformBlockBinding(gl_program, vertex_config_block_index, 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_vertex_config_buffer);
        glDrawElements(GL_TRIANGLES, cast(int) geometry.shared_index_count, GL_UNSIGNED_INT,
                       cast(void*) (geometry.shared_index_start * uint.sizeof));
    }
    
    void flush_and_render(T)(T geometry) {
        ShapeGroup converted_geometry;
        converted_geometry.shared_vertex_start = geometry.shared_vertex_start;
        converted_geometry.shared_vertex_count = geometry.shared_vertex_count;
        converted_geometry.shared_index_start  = geometry.shared_index_start;
        converted_geometry.shared_index_count  = geometry.shared_index_count;
        
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        
        apply_opengl_state(render_state);
        submit_geometry_to_opengl(converted_geometry, render_state);
    }
    
    void debug_draw_texture(Texture texture, int x, int y, int w, int h) {
    }
    
    void efb_copy_to_xfb() {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, efb_fbo);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, xfb_fbo);

        glColorMask(true, true, true, true);
        glBlitFramebuffer(render_state.efb_src_x, render_state.efb_src_y, render_state.efb_src_x + render_state.efb_src_w, render_state.efb_src_y + render_state.efb_src_h, render_state.efb_src_x, render_state.efb_src_y, render_state.efb_src_x + render_state.efb_src_w, render_state.efb_src_y + render_state.efb_src_h, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        xfb_has_data = true;
    }
    
    void efb_copy_to_texture(u8* buffer) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, efb_fbo);
        glReadPixels(render_state.efb_src_x, render_state.efb_src_y, render_state.efb_src_w, render_state.efb_src_h, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    }
    
    void clear_efb() {
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        glClearColor(
            render_state.clear_color_red / 255.0f,
            render_state.clear_color_green / 255.0f,
            render_state.clear_color_blue / 255.0f,
            render_state.clear_color_alpha / 255.0f
        );
        glClearDepth((render_state.clear_depth & 0xFFFFFF) / 16777215.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    }
    
    void update_gl_viewport(int gl_x, int gl_y, int gl_width, int gl_height) {
        glViewport(gl_x, gl_y, gl_width, gl_height);
    }
    
    void render_xfb() {
        if (xfb_has_data) {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glDisable(GL_DEPTH_TEST);
            glDisable(GL_BLEND);
            glDisable(GL_SCISSOR_TEST);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, xfb_color_texture);
            glUseProgram(xfb_shader_program);
            glUniform1i(glGetUniformLocation(xfb_shader_program, "u_texture"), 0);
            glBindVertexArray(xfb_vao);
            glDrawArrays(GL_TRIANGLES, 0, 6);
            glBindVertexArray(0);
        }
    }
}