// module emu.hw.hollywood.opengl_renderer;

// import bindbc.opengl;
// import emu.hw.hollywood.gl_objects;
// import emu.hw.hollywood.hollywood_types;
// import emu.hw.hollywood.texture;
// import emu.hw.hollywood.blitting_processor;
// import util.log;
// import std.file;
// import std.string;

// final class OpenGLRenderer {
//     private RenderState render_state;
    
//     private GlObjectManager gl_object_manager;
//     private BlittingProcessor blitting_processor;
    
//     private GLuint gl_program;
//     private int[8] texture_uniform_locations;
//     private int position_attr_location = -1;
//     private int normal_attr_location = -1;
//     private int texcoord_attr_location = -1;
//     private int color_attr_location = -1;
//     private int matrix_index_attr_location = -1;
//     private int position_matrix_uniform_location = -1;
//     private int texture_matrix_uniform_location = -1;
//     private int matrix_data_uniform_location = -1;
//     private int mvp_uniform_location = -1;
//     private uint tev_config_block_index = -1;
//     private uint vertex_config_block_index = -1;
//     private uint persistent_vertex_buffer = 0;
//     private uint persistent_tev_buffer = 0;
//     private uint persistent_vertex_config_buffer = 0;
//     private uint persistent_index_buffer = 0;
//     private float[256] general_matrix_ram;
    
//     private GLuint efb_fbo;
//     private GLuint efb_color_texture;
//     private GLuint efb_depth_texture;
//     private GLuint xfb_fbo;
//     private GLuint xfb_color_texture;
//     private GLuint xfb_shader_program;
//     private GLuint xfb_vao;
//     private GLuint xfb_vbo;
    
//     private Vertex* persistent_vertex_ptr = null;
//     private uint* persistent_index_ptr = null;
    
//     static immutable size_t MAX_VERTICES = 1024 * 1024;
//     static immutable size_t MAX_INDICES = MAX_VERTICES * 6;
    
//     this(GlObjectManager gl_object_manager, BlittingProcessor blitting_processor) {
//         this.gl_object_manager = gl_object_manager;
//         this.blitting_processor = blitting_processor;
//         render_state = RenderState();
//     }
    
//     void init_opengl() {
//         int uniform_buffer_alignment;
//         glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, &uniform_buffer_alignment);

//         glGenBuffers(1, &persistent_vertex_buffer);
//         glBindBuffer(GL_ARRAY_BUFFER, persistent_vertex_buffer);
//         glBufferStorage(GL_ARRAY_BUFFER, MAX_VERTICES * Vertex.sizeof, null, 
//                        GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
//         persistent_vertex_ptr = cast(Vertex*) glMapBufferRange(GL_ARRAY_BUFFER, 0, MAX_VERTICES * Vertex.sizeof,
//                                                               GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        
//         glGenBuffers(1, &persistent_tev_buffer);
//         glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
//         glBufferData(GL_UNIFORM_BUFFER, TevConfig.sizeof, null, GL_DYNAMIC_DRAW);

//         glGenBuffers(1, &persistent_vertex_config_buffer);
//         glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
//         glBufferData(GL_UNIFORM_BUFFER, VertexConfig.sizeof, null, GL_DYNAMIC_DRAW);

//         glGenBuffers(1, &persistent_index_buffer);
//         glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, persistent_index_buffer);
//         glBufferStorage(GL_ELEMENT_ARRAY_BUFFER, MAX_INDICES * uint.sizeof, null,
//                        GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
//         persistent_index_ptr = cast(uint*) glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, 0, MAX_INDICES * uint.sizeof,
//                                                            GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);

//         load_shaders();

//         render_state.projection_matrix[15] = 1;
        
//         glGenFramebuffers(1, &efb_fbo);
//         glGenTextures(1, &efb_color_texture);
//         glGenTextures(1, &efb_depth_texture);
        
//         glBindTexture(GL_TEXTURE_2D, efb_color_texture);
//         glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 528, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
//         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
//         glBindTexture(GL_TEXTURE_2D, efb_depth_texture);
//         glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, 640, 528, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, null);
//         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
//         glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
//         glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, efb_color_texture, 0);
//         glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, efb_depth_texture, 0);
        
//         glGenFramebuffers(1, &xfb_fbo);
//         glGenTextures(1, &xfb_color_texture);
        
//         glBindTexture(GL_TEXTURE_2D, xfb_color_texture);
//         glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 480, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
//         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//         glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
//         glBindFramebuffer(GL_FRAMEBUFFER, xfb_fbo);
//         glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, xfb_color_texture, 0);
//         glBindFramebuffer(GL_FRAMEBUFFER, 0);
        
//         init_xfb_shader();
//     }
    
//     private void init_xfb_shader() {
//         string xfb_vertex_text = readText("source/emu/hw/hollywood/shaders/xfb_vertex.glsl");
//         string xfb_fragment_text = readText("source/emu/hw/hollywood/shaders/xfb_fragment.glsl");
        
//         GLuint xfb_vertex_shader = glCreateShader(GL_VERTEX_SHADER);
//         auto xfb_vertex_src_ptr = xfb_vertex_text.ptr;
//         auto xfb_vertex_src_len = cast(int)xfb_vertex_text.length;
//         glShaderSource(xfb_vertex_shader, 1, &xfb_vertex_src_ptr, &xfb_vertex_src_len);
//         glCompileShader(xfb_vertex_shader);
        
//         GLuint xfb_fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
//         auto xfb_fragment_src_ptr = xfb_fragment_text.ptr;
//         auto xfb_fragment_src_len = cast(int)xfb_fragment_text.length;
//         glShaderSource(xfb_fragment_shader, 1, &xfb_fragment_src_ptr, &xfb_fragment_src_len);
//         glCompileShader(xfb_fragment_shader);
        
//         xfb_shader_program = glCreateProgram();
//         glAttachShader(xfb_shader_program, xfb_vertex_shader);
//         glAttachShader(xfb_shader_program, xfb_fragment_shader);
//         glLinkProgram(xfb_shader_program);
        
//         glDeleteShader(xfb_vertex_shader);
//         glDeleteShader(xfb_fragment_shader);
        
//         float[] xfb_quad_vertices = [
//             -1.0f, -1.0f,  0.0f, 1.0f,
//              1.0f, -1.0f,  1.0f, 1.0f,
//              1.0f,  1.0f,  1.0f, 0.0f,
//             -1.0f, -1.0f,  0.0f, 1.0f,
//              1.0f,  1.0f,  1.0f, 0.0f,
//             -1.0f,  1.0f,  0.0f, 0.0f
//         ];
        
//         glGenVertexArrays(1, &xfb_vao);
//         glGenBuffers(1, &xfb_vbo);
        
//         glBindVertexArray(xfb_vao);
//         glBindBuffer(GL_ARRAY_BUFFER, xfb_vbo);
//         glBufferData(GL_ARRAY_BUFFER, xfb_quad_vertices.length * float.sizeof, xfb_quad_vertices.ptr, GL_STATIC_DRAW);
        
//         glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)0);
//         glEnableVertexAttribArray(0);
        
//         glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)(2 * float.sizeof));
//         glEnableVertexAttribArray(1);
        
//         glBindVertexArray(0);
//     }
    
//     private void load_shaders() {
//         auto vertex_shader   = glCreateShader(GL_VERTEX_SHADER);
//         auto fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);	
//         string vertex_text   = readText("source/emu/hw/hollywood/shaders/vertex.glsl");
//         string fragment_text = readText("source/emu/hw/hollywood/shaders/fragment.glsl");

//         auto vertex_src_ptr = vertex_text.ptr;
//         auto vertex_src_len = cast(int)vertex_text.length;
//         glShaderSource(vertex_shader, 1, &vertex_src_ptr, &vertex_src_len);
//         glCompileShader(vertex_shader);

//         auto fragment_src_ptr = fragment_text.ptr;
//         auto fragment_src_len = cast(int)fragment_text.length;
//         glShaderSource(fragment_shader, 1, &fragment_src_ptr, &fragment_src_len);
//         glCompileShader(fragment_shader);

//         gl_program = glCreateProgram();
//         glAttachShader(gl_program, vertex_shader);
//         glAttachShader(gl_program, fragment_shader);
//         glLinkProgram(gl_program);

//         position_attr_location         = glGetAttribLocation(gl_program,  "aPosition");
//         normal_attr_location           = glGetAttribLocation(gl_program,  "aNormal");
//         texcoord_attr_location         = glGetAttribLocation(gl_program,  "aTexCoord");
//         color_attr_location            = glGetAttribLocation(gl_program,  "aColor");
//         matrix_index_attr_location     = glGetAttribLocation(gl_program,  "aMatrixIndex");
//         position_matrix_uniform_location = glGetUniformLocation(gl_program, "uPositionMatrix");
//         texture_matrix_uniform_location  = glGetUniformLocation(gl_program, "uTextureMatrix");
//         matrix_data_uniform_location     = glGetUniformLocation(gl_program, "uMatrixData");
//         mvp_uniform_location             = glGetUniformLocation(gl_program, "uMVP");
//         tev_config_block_index           = glGetUniformBlockIndex(gl_program, "TevBlock");
//         vertex_config_block_index        = glGetUniformBlockIndex(gl_program, "VertexBlock");

//         for (int i = 0; i < 8; i++) {
//             import std.string;
//             auto texture_name = format("tex%d", i);
//             texture_uniform_locations[i] = glGetUniformLocation(gl_program, texture_name.ptr);
//         }

//         glDeleteShader(vertex_shader);
//         glDeleteShader(fragment_shader);
//     }
    
//     const(RenderState)* get_render_state() const {
//         return &render_state;
//     }
    
//     RenderState* get_render_state_for_modification() {
//         return &render_state;
//     }
    
//     void set_general_matrix_ram(float[256] matrix_ram) {
//         general_matrix_ram = matrix_ram;
//     }
    
//     private uint current_vertex_offset = 0;
//     private uint current_index_offset = 0;
    
//     Vertex* allocate_vertex() {
//         if (current_vertex_offset >= MAX_VERTICES) {
//             return null;
//         }
//         return &persistent_vertex_ptr[current_vertex_offset++];
//     }
    
//     uint* allocate_index() {
//         if (current_index_offset >= MAX_INDICES) {
//             return null;
//         }
//         return &persistent_index_ptr[current_index_offset++];
//     }
    
//     private uint gc_blend_factor_to_gl(int gc_factor) {
//         final switch (gc_factor) {
//             case 0: return GL_ZERO;
//             case 1: return GL_ONE;
//             case 2: return GL_SRC_COLOR;
//             case 3: return GL_ONE_MINUS_SRC_COLOR;
//             case 4: return GL_SRC_ALPHA;
//             case 5: return GL_ONE_MINUS_SRC_ALPHA;
//             case 6: return GL_DST_ALPHA;
//             case 7: return GL_ONE_MINUS_DST_ALPHA;
//         }
//     }
    
//     void apply_opengl_state(RenderState render_state) {
//         glUseProgram(gl_program);
//         glClearColor(
//             blitting_processor.get_copy_clear_color_red() / 255.0f,
//             blitting_processor.get_copy_clear_color_green() / 255.0f, 
//             blitting_processor.get_copy_clear_color_blue() / 255.0f,
//             blitting_processor.get_copy_clear_color_alpha() / 255.0f
//         ); 
        
//         gl_object_manager.deallocate_all_objects();
//         glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE, render_state.texture[0].tex_matrix.ptr);
//         glUniformMatrix4fv(mvp_uniform_location, 1, GL_FALSE, render_state.projection_matrix.ptr);
//         glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
//         glBufferSubData(GL_UNIFORM_BUFFER, 0, TevConfig.sizeof, &render_state.tev_config);
//         glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_tev_buffer);
//         glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
//         glBufferSubData(GL_UNIFORM_BUFFER, 0, VertexConfig.sizeof, &render_state.vertex_config);
//         glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_vertex_config_buffer);
//         if (render_state.arithmetic_blending_enable) {
//             glEnable(GL_BLEND);
//             auto op1 = gc_blend_factor_to_gl(render_state.blend_source);
//             auto op2 = gc_blend_factor_to_gl(render_state.blend_destination);
//             glBlendFunc(op1, op2);
//         } else {
//             glDisable(GL_BLEND);
//         }
//         while (render_state.enabled_textures_bitmap != 0) {
//             int i = cast(int) render_state.enabled_textures_bitmap.bfs;
//             render_state.enabled_textures_bitmap &= ~(1 << i);
//             glActiveTexture(GL_TEXTURE0 + i);
//             glBindTexture(GL_TEXTURE_2D, render_state.texture[i].texture_id);
//             glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//             glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//             final switch (render_state.texture[i].wrap_s) {
//                 case TextureWrap.Clamp:
//                     glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//                     break;
                
//                 case TextureWrap.Repeat:
//                     glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
//                     break;
                
//                 case TextureWrap.Mirror:
//                     glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_MIRRORED_REPEAT);
//                     break;
//             }
//             final switch (render_state.texture[i].wrap_t) {
//                 case TextureWrap.Clamp:
//                     glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//                     break;
                
//                 case TextureWrap.Repeat:
//                     glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
//                     break;
                
//                 case TextureWrap.Mirror:
//                     glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_MIRRORED_REPEAT);
//                     break;
//             }
//             glUniform1i(texture_uniform_locations[i], i);
//         }
//         glColorMask(
//             render_state.color_update_enable, 
//             render_state.color_update_enable, 
//             render_state.color_update_enable, 
//             render_state.alpha_update_enable
//         );
//         if (render_state.depth_test_enabled) {
//             glEnable(GL_DEPTH_TEST);
//             glDepthFunc(render_state.depth_func);
//         } else {
//             glDisable(GL_DEPTH_TEST);
//         }
//         glDepthMask(render_state.depth_write_enabled ? GL_TRUE : GL_FALSE);
//         final switch (render_state.cull_mode) {
//             case 0:
//                 // glDisable(GL_CULL_FACE);
//                 break;
//             case 1:
//                 // glEnable(GL_CULL_FACE);
//                 // glCullFace(GL_FRONT);
//                 break;
//             case 2:
//                 // glEnable(GL_CULL_FACE);
//                 // glCullFace(GL_BACK);
//                 break;
//         }
//     }
    
//     void submit_geometry_to_opengl(ShapeGroup geometry, RenderState render_state) {
//         log_hollywood("Submitting shape group to OpenGL (%d %d %d %d)", geometry.shared_vertex_count, geometry.shared_vertex_start, geometry.shared_index_count, geometry.shared_index_start);
        
//         uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
//         glBindVertexArray(vertex_array_object);
//         glBindBuffer(GL_ARRAY_BUFFER, persistent_vertex_buffer);
//         glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, persistent_index_buffer);
//         size_t base_offset = geometry.shared_vertex_start * Vertex.sizeof;
        
//         glEnableVertexAttribArray(position_attr_location);
//         glVertexAttribPointer(position_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 0));
//         glEnableVertexAttribArray(normal_attr_location);
//         glVertexAttribPointer(normal_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 3 * float.sizeof));
//         glEnableVertexAttribArray(texcoord_attr_location);
//         glVertexAttribPointer(texcoord_attr_location, 2, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 6 * float.sizeof));
//         glEnableVertexAttribArray(color_attr_location);
//         glVertexAttribPointer(color_attr_location, 4, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 22 * float.sizeof));
//         glEnableVertexAttribArray(matrix_index_attr_location);
//         glVertexAttribIPointer(matrix_index_attr_location, 1, GL_INT, Vertex.sizeof, cast(void*) (base_offset + 30 * float.sizeof));
            
//         if (render_state.uses_per_vertex_matrices) {
//             glUniform1fv(matrix_data_uniform_location, 256, general_matrix_ram.ptr);
//         } else {
//             glUniformMatrix4x3fv(position_matrix_uniform_location, 1, GL_TRUE, render_state.position_matrix.ptr);
//         }
//         glUniformMatrix4x3fv(texture_matrix_uniform_location,  1, GL_TRUE,  render_state.texture[0].tex_matrix.ptr);
//         glUniformMatrix4fv  (mvp_uniform_location,             1, GL_FALSE, render_state.projection_matrix.ptr);
//         glUniformBlockBinding(gl_program, tev_config_block_index, 0);
//         glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_tev_buffer);
//         glUniformBlockBinding(gl_program, vertex_config_block_index, 1);
//         glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_vertex_config_buffer);
//         glDrawElements(GL_TRIANGLES, cast(int) geometry.shared_index_count, GL_UNSIGNED_INT,
//                        cast(void*) (geometry.shared_index_start * uint.sizeof));
//         log_hollywood("Drawing shape");
//     }
// }