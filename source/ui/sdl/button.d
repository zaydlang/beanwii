module ui.sdl.button;

import bindbc.opengl;
import bindbc.sdl;
import ui.sdl.color;
import ui.sdl.drawable;
import ui.sdl.font;
import ui.sdl.shaders.shader;
import ui.sdl.updatable;
import util.log;

final class SdlButton : Drawable, Updatable {
    float[12] vertices;
    
    Color default_color;
    Color hover_color;
    Color click_color;
    
    Color current_color;
    Color text_color;

    uint vao;
    uint vbo;

    int x;
    int y;
    int w;
    int h;

    GLint shader;

    RenderedTextHandle text_handle;
    Font font;

    this(int x, int y, int w, int h, Color background_color, Color text_color, Font font, string text, GLint shader) {
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
    }

    override void draw() {
        glUseProgram(shader);

        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
    
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof, vertices.ptr, GL_STATIC_DRAW);
    
        auto position_location = glGetAttribLocation(shader, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 3, GL_FLOAT, GL_FALSE, 0, cast(void*) 0);
    
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
        glUniform4fv(1, 1, cast(float*) &current_color);

        font.set_string(text_handle, this.text_color, "Pause", x, y, w, h);
    }

    override void update(int mouse_x, int mouse_y, int mouse_state) {
        log_frontend("mouse_x: %d, mouse_y: %d, mouse_state: %d (%d vs %d)", mouse_x, mouse_y, mouse_state, x, y);

        if (mouse_x >= x && mouse_x <= x + w && mouse_y >= y && mouse_y <= y + h) {
            if (mouse_state & SDL_BUTTON(SDL_BUTTON_LEFT)) {
                current_color = click_color;
            } else {
                current_color = hover_color;
            }
        } else {
            current_color = default_color;
        }
    }
}
