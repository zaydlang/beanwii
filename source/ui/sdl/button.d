module ui.sdl.button;

import bindbc.opengl;
import bindbc.sdl;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class SdlButton : Widget {
    float[12] vertices;
    
    Color default_color;
    Color hover_color;
    Color click_color;
    
    Color current_color;
    Color text_color;

    uint vao;
    uint vbo;

    GLint shader;

    RenderedTextHandle text_handle;
    string text;
    Font font;

    bool clicked = false;
    bool hovered = false;
    void delegate(void*) on_click;
    void delegate(void*) on_hover_start;
    void delegate(void*) on_hover_end;
    void* user_data;

    this(int x, int y, int w, int h, Color background_color, Color text_color, Font font, string text, GLint shader, void delegate(void*) on_click, void delegate(void*) on_hover_start, void delegate(void*) on_hover_end, void* user_data) {
        super(x, y, w, h);

        this.default_color = background_color;
        this.hover_color = darken(background_color, 0.15f);
        this.click_color = darken(background_color, 0.3f);
        this.current_color = background_color;
        this.text_color = text_color;

        this.shader = shader;
        this.font = font;

        glUseProgram(shader);
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        
        text_handle = font.obtain_text_handle();
        this.text = text;

        this.on_click = on_click;
        this.on_hover_start = on_hover_start;
        this.on_hover_end = on_hover_end;
        this.user_data = user_data;
    }

    override void draw() {
        vertices = [
            x, y, 0.0f,
            x + w, y, 0.0f,
            x + w, y + h, 0.0f,
            x, y + h, 0.0f,
        ];

        glUseProgram(shader);
        log_frontend("locations: %d, %d, %d", glGetUniformLocation(shader, "color"), glGetUniformLocation(shader, "in_Position"), shader);
        glUniform4f(glGetUniformLocation(shader, "color"), current_color.r, current_color.g, current_color.b, current_color.a);

        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);

        auto position_location = glGetAttribLocation(shader, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, 0, cast(void*) 0);

        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof, vertices.ptr, GL_STATIC_DRAW);
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

        font.set_string(text_handle, this.text_color, Justify.Center, this.text, x, y, w, h);
    }

    override void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {
        if (mouse_x >= x && mouse_x <= x + w && mouse_y >= y && mouse_y <= y + h) {
            if (mouse_state & SDL_BUTTON(SDL_BUTTON_LEFT)) {
                current_color = click_color;

                if (!clicked) {
                    clicked = true;
                    on_click(user_data);
                }
            } else {
                current_color = hover_color;
                clicked = false;

                if (!hovered) {
                    hovered = true;
                    on_hover_start(user_data);
                }
            }
        } else {
            current_color = default_color;
            clicked = false;

            if (hovered) {
                on_hover_end(user_data);
                hovered = false;
            }
        }
    }
}
