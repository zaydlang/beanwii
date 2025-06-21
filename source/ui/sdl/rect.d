module ui.sdl.rect;

import bindbc.opengl;
import bindbc.sdl;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class Rect : Widget {
    float[12] vertices;
    
    Color color;

    uint vao;
    uint vbo;

    GLint shader;

    this(int x, int y, int w, int h, Color color, GLint shader) {
        super(x, y, w, h);

        this.color = color;
        this.shader = shader;

        log_frontend("glUseProgram(%d) for Rect at (%d, %d, %d, %d)", shader, x, y, w, h);
        glUseProgram(shader);
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
    }

    override void draw() {
        vertices = [
            x, y, 0.0f,
            x + w, y, 0.0f,
            x + w, y + h, 0.0f,
            x, y + h, 0.0f,
        ];

        glUseProgram(shader);
        glUniform4f(glGetUniformLocation(shader, "color"), color.r, color.g, color.b, color.a);

        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);

        auto position_location = glGetAttribLocation(shader, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, 0, cast(void*) 0);

        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof, vertices.ptr, GL_STATIC_DRAW);
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
    }

    override void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {}
}
