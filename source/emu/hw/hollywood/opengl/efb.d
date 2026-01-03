module emu.hw.hollywood.opengl.efb;

import bindbc.opengl;
import emu.hw.hollywood.gl_objects;
import std.file;
import std.string;
import util.log;
import util.number;

final class EFBCopyOptimizer {
    private GLuint compute_shader_program = 0;
    private GLuint efb_copy_ubo = 0;
    private GlObjectManager gl_objects;

    struct EFBCopyParams {
        align(16) int[4] channel_mask;
        align(8) float[2] src_offset;
        align(8) float[2] src_size;
        align(8) int[2] dst_size;
    }

    this(GlObjectManager gl_objects) {
        this.gl_objects = gl_objects;
        // Initialize compute shader
        string compute_source = readText("source/emu/hw/hollywood/shaders/efb_copy_compute.glsl");

        GLuint compute_shader = glCreateShader(GL_COMPUTE_SHADER);
        const char* compute_ptr = compute_source.toStringz();
        glShaderSource(compute_shader, 1, &compute_ptr, null);
        glCompileShader(compute_shader);

        GLint compute_success;
        glGetShaderiv(compute_shader, GL_COMPILE_STATUS, &compute_success);
        if (!compute_success) {
            char[512] info_log;
            glGetShaderInfoLog(compute_shader, 512, null, info_log.ptr);
            error_opengl("EFB compute shader compilation failed: %s", info_log.ptr);
        }

        compute_shader_program = glCreateProgram();
        glAttachShader(compute_shader_program, compute_shader);
        glLinkProgram(compute_shader_program);

        GLint program_success;
        glGetProgramiv(compute_shader_program, GL_LINK_STATUS, &program_success);
        if (!program_success) {
            char[512] info_log;
            glGetProgramInfoLog(compute_shader_program, 512, null, info_log.ptr);
            error_opengl("EFB compute shader program linking failed: %s", info_log.ptr);
        }

        glDeleteShader(compute_shader);

        // Create UBO
        glGenBuffers(1, &efb_copy_ubo);
        glBindBuffer(GL_UNIFORM_BUFFER, efb_copy_ubo);
        glBufferData(GL_UNIFORM_BUFFER, EFBCopyParams.sizeof, null, GL_DYNAMIC_DRAW);
        
        GLuint block_index = glGetUniformBlockIndex(compute_shader_program, "EFBCopyParams");
        if (block_index != GL_INVALID_INDEX) {
            glUniformBlockBinding(compute_shader_program, block_index, 0);
        }
    }

    GLuint copy_efb_to_texture(GLuint efb_color_texture, u32 src_x, u32 src_y, u32 width, u32 height, u8 format, bool mipmap) {
        int[4] channel_mask = get_channel_mask(format);
        
        EFBCopyParams params;
        params.channel_mask = channel_mask;
        params.src_offset = [cast(float) src_x, cast(float) src_y];
        params.src_size = [cast(float) width, cast(float) height];
        params.dst_size = [cast(int)(mipmap ? width / 2 : width), cast(int)(mipmap ? height / 2 : height)];
        
        u32 output_width = mipmap ? width / 2 : width;
        u32 output_height = mipmap ? height / 2 : height;
        
        GLuint output_texture = gl_objects.allocate_efb_object();
        glBindTexture(GL_TEXTURE_2D, output_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, output_width, output_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        update_ubo(params);

        glUseProgram(compute_shader_program);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, efb_color_texture);

        glBindImageTexture(0, output_texture, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8);

        GLuint groups_x = cast(GLuint)((output_width + 15) / 16);
        GLuint groups_y = cast(GLuint)((output_height + 7) / 8);
        glDispatchCompute(groups_x, groups_y, 1);

        glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT | GL_TEXTURE_FETCH_BARRIER_BIT);

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
}
