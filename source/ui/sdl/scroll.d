module ui.sdl.scroll;

import bindbc.opengl;
import bindbc.sdl;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class Scroll : Widget {
    float[12] vertices;

    int x;
    int y;
    int w;
    int h;

    Color background_color;
    Color text_color;

    uint vao;
    uint vbo;

    GLint shader;

    Widget[] items;

    int scroll_offset = 0;
    int max_scroll_offset = 0;

    Font font;
    string text;
    RenderedTextHandle text_handle;

    this(int x, int y, int w, int h, Color background_color, GLint shader, Color text_color, Font font, string title) {
        super(x, y, w, h);

        vertices = [
            x, y, 0.0f,
            x + w, y, 0.0f,
            x + w, y + h, 0.0f,
            x, y + h, 0.0f,
        ];

        this.x = x;
        this.y = y;
        this.w = w;
        this.h = h;

        this.background_color = background_color;

        this.shader = shader;

        glUseProgram(shader);
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);

        text_handle = font.obtain_text_handle();
        this.text = title;
        this.font = font;
        this.text_color = text_color;
    }

    void set_items(Widget[] new_items) {
        items = [];
        
        int total_content_height = 5;
        for (int i = 0; i < new_items.length; i++) {
            items ~= new_items[i];
            total_content_height += new_items[i].get_h() + 5;
        }
        
        int scrollable_area = h - 50;
        max_scroll_offset = total_content_height - scrollable_area;

        if (max_scroll_offset < 0) {
            max_scroll_offset = 0;
        }
    }

    override void draw() {
        glUseProgram(shader);

        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof, vertices.ptr, GL_STATIC_DRAW);

        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * float.sizeof, cast(void*)0);
        glEnableVertexAttribArray(0);

        glUniform4f(glGetUniformLocation(shader, "color"), background_color.r, background_color.g, background_color.b, background_color.a);

        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

        font.set_string(text_handle, this.text_color, Justify.Center, this.text, x, y + h - 50, w, 50);

        glEnable(GL_SCISSOR_TEST);
        glScissor(x, y + 5, w, h - 45);

        int current_offset = -scroll_offset;
        for (int i = 0; i < items.length; i++) {
            items[i].set_x(x + 5);
            items[i].set_y(y + h - current_offset - 5 - items[i].get_h() - 50);
            items[i].set_w(w - 10);

            items[i].draw();

            current_offset += items[i].get_h() + 5;
        }

        glDisable(GL_SCISSOR_TEST);
    }

    override void update(int mouse_x, int mouse, int mouse_state, long mouse_wheel) {
        if (mouse_x >= x && mouse_x <= x + w && mouse >= y && mouse <= y + h) {
            scroll_offset -= mouse_wheel * 15;

            if (scroll_offset < 0) {
                scroll_offset = 0;
            }

            if (scroll_offset > max_scroll_offset) {
                scroll_offset = max_scroll_offset;
            }
        }

        for (int i = 0; i < items.length; i++) {
            items[i].update(mouse_x, mouse, mouse_state, mouse_wheel);
        }
    }
}

