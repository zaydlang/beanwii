module emu.hw.hollywood.gl_objects;

import bindbc.opengl;

final class GlObjectManager {
    uint[] vertex_array_objects;
    int vertex_array_objects_count;
    uint[] vertex_buffer_objects;
    int vertex_buffer_objects_count;
    uint[] uniform_buffer_objects;
    int uniform_buffer_objects_count;
    uint[] texture_objects;
    int texture_objects_count;

    void deallocate_all_objects() {
        vertex_array_objects_count = 0;
        vertex_buffer_objects_count = 0;
        uniform_buffer_objects_count = 0;
    }

    uint allocate_vertex_array_object() {
        if (vertex_array_objects_count == vertex_array_objects.length) {
            uint new_vertex_array_object;
            glGenVertexArrays(1, &new_vertex_array_object);
            vertex_array_objects ~= new_vertex_array_object;

            return new_vertex_array_object;
        }

        return vertex_array_objects[vertex_array_objects_count++];
    }

    uint allocate_vertex_buffer_object() {
        if (vertex_buffer_objects_count == vertex_buffer_objects.length) {
            uint new_vertex_buffer_object;
            glGenBuffers(1, &new_vertex_buffer_object);
            vertex_buffer_objects ~= new_vertex_buffer_object;

            return new_vertex_buffer_object;
        }

        return vertex_buffer_objects[vertex_buffer_objects_count++];
    }

    uint allocate_uniform_buffer_object() {
        if (uniform_buffer_objects_count == uniform_buffer_objects.length) {
            uint new_uniform_buffer_object;
            glGenBuffers(1, &new_uniform_buffer_object);
            uniform_buffer_objects ~= new_uniform_buffer_object;

            return new_uniform_buffer_object;
        }

        return uniform_buffer_objects[uniform_buffer_objects_count++];
    }

    uint allocate_texture_object() {
        if (texture_objects_count == texture_objects.length) {
            uint new_texture_object;
            glGenTextures(1, &new_texture_object);
            texture_objects ~= new_texture_object;

            return new_texture_object;
        }

        return texture_objects[texture_objects_count++];
    }
}