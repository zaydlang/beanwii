module ui.sdl.hollywood.texturewidget;

import bindbc.opengl;
import bindbc.sdl;
import emu.hw.hollywood.hollywood;
import ui.sdl.checkbox;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.rect;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class TextureWidget : Widget {
    float[12] vertices;

    GLint tex_shader;
    Hollywood hollywood;
    Texture texture;
    Rect rect;
    Checkbox checkbox;

    this(int x, int y, int w, int h, Hollywood hollywood, GLint bg_shader, GLint tex_shader, Color background, Texture texture, Font font) {
        super(x, y, w, h);

        this.hollywood = hollywood;
        this.texture = texture;
        this.tex_shader = tex_shader;

        rect = new Rect(x, y, w, h, background, bg_shader);
        checkbox = new Checkbox(x + 10, y + 10, 20, 20, lighten(background, 0.1f), background, font, bg_shader);
    }

    override void draw() {
        rect.draw();
        // checkbox.draw();
        glUseProgram(tex_shader);

        hollywood.debug_draw_texture(texture, x, y, w, h);
    }

    override void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {}
}
