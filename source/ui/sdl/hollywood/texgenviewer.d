module ui.sdl.hollywood.texgenviewer;

import bindbc.opengl;
import bindbc.sdl;
import emu.hw.hollywood.hollywood;
import ui.sdl.checkbox;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.matrixviewer;
import ui.sdl.rect;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import util.log;

final class TexGenViewer : Widget {
    float[12] vertices;

    GLint tex_shader;
    Rect rect;
    Checkbox checkbox;

    MatrixViewer tex_viewer;
    MatrixViewer dualtex_viewer;
    RenderedTextHandle tex_handle;
    RenderedTextHandle dualtex_handle;
    RenderedTextHandle normalize_before_dualtex;
    Font font;

    int mat_viewer_height;

    this(int x, int y, int w, int h, Texture texture, GLint shader, Color background, Font font, Font mat_font) {
        super(x, y, w, h);

        this.tex_shader = tex_shader;
        this.font = font;

        mat_viewer_height = (h - 20 * 2 - 30 - 10 * 2) / 2;
        rect = new Rect(x, y, w, h, from_hex(0xCAF0F8), shader);
        checkbox = new Checkbox(x + h / 2 + 120, y + 15 + mat_viewer_height + 10 + 40 - 5, 20, 20, background, from_hex(0xCAF0F8), font, shader);
    
        tex_viewer = new MatrixViewer(x + 10, y + mat_viewer_height + 10 + 30 + 20, w - 20, mat_viewer_height, background, from_hex(0x444444), mat_font, shader, 
            texture.tex_matrix);

        dualtex_viewer = new MatrixViewer(x + 10, y + 10, w - 20, mat_viewer_height, background, from_hex(0x444444), mat_font, shader, 
            texture.dualtex_matrix);

        // checkbox = new Checkbox(x, y / 2)
        checkbox.on = texture.normalize_before_dualtex;

        tex_handle = font.obtain_text_handle();
        dualtex_handle = font.obtain_text_handle();
        normalize_before_dualtex = font.obtain_text_handle();
    }

    override void draw() {
        rect.draw();
        checkbox.draw();
        // glUseProgram(tex_shader);

        // hollywood.debug_draw_texture(texture, x, y, w, h);
        tex_viewer.draw();
        dualtex_viewer.draw();

        font.set_string(tex_handle, from_hex(0x444444), Justify.Center, "Tex Matrix",
            cast(float) x, 
            cast(float) y + h - 30,
            cast(float) w, 
            cast(float) 20);
        font.set_string(dualtex_handle, from_hex(0x444444), Justify.Center, "DualTex Matrix", 
            cast(float) x,
            cast(float) y + mat_viewer_height + 10,
            cast(float) w,
            cast(float) 20);
        font.set_string(normalize_before_dualtex, from_hex(0x444444), Justify.Center, "Normalize before DualTex:    ",
            cast(float) x + 10, 
            cast(float) y + 10 + mat_viewer_height + 10 + 20 - 5, 
            cast(float) w - 20, 
            cast(float) 30);
    }

    override void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {}
}