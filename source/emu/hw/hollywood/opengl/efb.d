module emu.hw.hollywood.opengl.efb;

import bindbc.opengl;
import emu.hw.hollywood.gl_objects;
import std.file;
import std.string;
import util.log;
import util.number;

final class EFBCopyOptimizer {
    private GLuint channel_shader_program = 0;
    private GLuint efb_copy_ubo = 0;
    private GLuint vertex_shader = 0;
    private GLuint fragment_shader = 0;
    private GLuint quad_vao = 0;
    private GLuint quad_vbo = 0;
    private GlObjectManager gl_objects;

    struct EFBCopyParams {
        align(16) int[4] channel_mask;
        align(8) float[2] src_offset;
        align(8) float[2] src_size;
    }

    this(GlObjectManager gl_objects) {
        this.gl_objects = gl_objects;
        // Initialize shaders
        string vertex_source = readText("source/emu/hw/hollywood/shaders/efb_copy_vertex.glsl");
        string fragment_source = readText("source/emu/hw/hollywood/shaders/efb_copy_fragment.glsl");
        
        vertex_shader = glCreateShader(GL_VERTEX_SHADER);
        const char* vertex_ptr = vertex_source.toStringz();
        glShaderSource(vertex_shader, 1, &vertex_ptr, null);
        glCompileShader(vertex_shader);
        
        GLint vertex_success;
        glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &vertex_success);
        if (!vertex_success) {
            char[512] info_log;
            glGetShaderInfoLog(vertex_shader, 512, null, info_log.ptr);
            error_opengl("EFB vertex shader compilation failed: %s", info_log.ptr);
        }
        
        fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
        const char* fragment_ptr = fragment_source.toStringz();
        glShaderSource(fragment_shader, 1, &fragment_ptr, null);
        glCompileShader(fragment_shader);
        
        GLint fragment_success;
        glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &fragment_success);
        if (!fragment_success) {
            char[512] info_log;
            glGetShaderInfoLog(fragment_shader, 512, null, info_log.ptr);
            error_opengl("EFB fragment shader compilation failed: %s", info_log.ptr);
        }
        
        channel_shader_program = glCreateProgram();
        glAttachShader(channel_shader_program, vertex_shader);
        glAttachShader(channel_shader_program, fragment_shader);
        glLinkProgram(channel_shader_program);
        
        GLint program_success;
        glGetProgramiv(channel_shader_program, GL_LINK_STATUS, &program_success);
        if (!program_success) {
            char[512] info_log;
            glGetProgramInfoLog(channel_shader_program, 512, null, info_log.ptr);
            error_opengl("EFB shader program linking failed: %s", info_log.ptr);
        }
        
        
        // Create UBO
        glGenBuffers(1, &efb_copy_ubo);
        glBindBuffer(GL_UNIFORM_BUFFER, efb_copy_ubo);
        glBufferData(GL_UNIFORM_BUFFER, EFBCopyParams.sizeof, null, GL_DYNAMIC_DRAW);
        
        GLuint block_index = glGetUniformBlockIndex(channel_shader_program, "EFBCopyParams");
        if (block_index != GL_INVALID_INDEX) {
            glUniformBlockBinding(channel_shader_program, block_index, 0);
        }
        
        // Create fullscreen quad
        float[] quad_vertices = [
            -1.0f, -1.0f,
             1.0f, -1.0f,
             1.0f,  1.0f,
            -1.0f, -1.0f,
             1.0f,  1.0f,
            -1.0f,  1.0f
        ];
        
        glGenVertexArrays(1, &quad_vao);
        glGenBuffers(1, &quad_vbo);
        
        glBindVertexArray(quad_vao);
        glBindBuffer(GL_ARRAY_BUFFER, quad_vbo);
        glBufferData(GL_ARRAY_BUFFER, quad_vertices.length * float.sizeof, quad_vertices.ptr, GL_STATIC_DRAW);
        
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * float.sizeof, cast(void*)0);
        glEnableVertexAttribArray(0);
        
        glBindVertexArray(0);
    }

    GLuint copy_efb_to_texture(GLuint efb_color_texture, u32 src_x, u32 src_y, u32 width, u32 height, u8 format, bool mipmap) {
        int[4] channel_mask = get_channel_mask(format);
        
        EFBCopyParams params;
        params.channel_mask = channel_mask;
        params.src_offset = [cast(float) src_x, cast(float) src_y];
        params.src_size = [cast(float) width, cast(float) height];
        
        u32 output_width = mipmap ? width / 2 : width;
        u32 output_height = mipmap ? height / 2 : height;
        
        GLuint output_texture = gl_objects.allocate_efb_object();
        glBindTexture(GL_TEXTURE_2D, output_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, output_width, output_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        GLuint output_fbo;
        glGenFramebuffers(1, &output_fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, output_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, output_texture, 0);
        
        update_ubo(params);
        render_to_fbo(efb_color_texture, output_fbo, output_width, output_height);
        
        glDeleteFramebuffers(1, &output_fbo);
        
        return output_texture;
    }

    private int[4] get_channel_mask(u8 copy_format) {
        switch (copy_format) {
            case 0x8:  // R8
                return [1, 0, 0, 0];
            case 0xB:  // RG8
                return [1, 1, 0, 0];
            case 0x7:  // A8
                return [0, 0, 0, 1];
            case 0x1:  // I8 
                return [1, 1, 1, 0];
            default:   // rest
                return [1, 1, 1, 1];
        }
    }

    private void update_ubo(ref EFBCopyParams params) {
        glBindBuffer(GL_UNIFORM_BUFFER, efb_copy_ubo);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, EFBCopyParams.sizeof, &params);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, efb_copy_ubo);
    }

    private void render_to_fbo(GLuint efb_color_texture, GLuint output_fbo, u32 width, u32 height) {
        glBindFramebuffer(GL_FRAMEBUFFER, output_fbo);
        glViewport(0, 0, width, height);
        
        glUseProgram(channel_shader_program);
        
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, efb_color_texture);
        glUniform1i(glGetUniformLocation(channel_shader_program, "efb_color"), 0);
        
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_BLEND);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        
        glBindVertexArray(quad_vao);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        glBindVertexArray(0);
        
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
}