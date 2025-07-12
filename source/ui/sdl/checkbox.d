module ui.sdl.checkbox;

import bindbc.opengl;
import bindbc.sdl;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.rect;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class Checkbox : Widget {
    Rect border;
    Rect inner;
    RenderedTextHandle text_handle;
    Font font;

    bool on;

    this(int x, int y, int w, int h, Color border_color, Color inner_color, Font font, GLint shader) {
        super(x, y, w, h);

        this.font = font;

        // border = new Rect(x, y, w, h, border_color, shader);
        // inner = new Rect(x + 2, y + 2, w - 4, h - 4, inner_color, shader);
        on = false;
        text_handle = font.obtain_text_handle();
    }

    override void draw() {
        // border.draw();
        // inner.draw();
        font.set_string(text_handle, on ? from_hex(0xb1ef88) : from_hex(0xef9688), Justify.Center, on ? "O" : "X", x, y, w, h);
    }

    override void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {}
}
