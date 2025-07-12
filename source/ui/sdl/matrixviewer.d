module ui.sdl.matrixviewer;

import bindbc.opengl;
import bindbc.sdl;
import std.format;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class MatrixViewer : Widget {
    float[12] vertices;
    
    Color color;
    Color font_color;

    uint vao;
    uint vbo;

    GLint shader;

    float[12] matrix;
    RenderedTextHandle[16] text_handles;
    Font font;

    this(int x, int y, int w, int h, Color color, Color font_color, Font font, GLint shader, float [12] matrix) {
        super(x, y, w, h);

        this.color = color;
        this.font_color = font_color;
        this.shader = shader;

        glUseProgram(shader);
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);

        for (int i = 0; i < 16; i++) {
            text_handles[i] = font.obtain_text_handle();
        }

        this.matrix = matrix;
        this.font = font;
    }

    override void draw() {
        log_frontend("glUseProgram(%d) for MatrixViewer at (%d, %d, %d, %d)", shader, x, y, w, h);
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

        for (int i = 0; i < 12; i++) {
            int xoff = i % 4;
            int yoff = 2 - (i / 4) + 1;
            float value = matrix[i];
            string text = "%f".format(value);
            font.set_string(text_handles[i], font_color,
                Justify.Center, text,
                x + xoff * (w / 4.0f),
                y + yoff * (h / 4.0f),
                w / 4.0f, h / 4.0f
            );
        }

        for (int i = 0; i < 4; i++) {
            font.set_string(text_handles[i + 12], font_color, Justify.Center, "-", x + i * (w / 4.0f), y, w / 4.0f, h / 4.0f);
        }
    }

    override void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {}
}
