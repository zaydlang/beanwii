module ui.sdl.tab;

import bindbc.opengl;
import bindbc.sdl;
import ui.sdl.button;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.rect;
import ui.sdl.shaders.shader;
import ui.sdl.widget;
import std.format;

final class TabManager : Widget {
    int x;
    int y;
    int w;
    int h;
    GLint shader;
    Color background_color;

    Widget[] tabs;
    Widget[] children;
    SdlButton[] buttons;
    int active_tab_idx;

    this(int x, int y, int w, int h, Widget[] tabs, Color background_color, Font font, GLint shader) {
        super(x, y, w, h);
        
        this.active_tab_idx = 0;
        this.shader = shader;
        this.x = x;
        this.y = y;
        this.w = w;
        this.h = h;

        children = [
            new Rect(x, y, w, h, background_color, shader),
        ];

        this.tabs = [];

        for (int i = 0; i < tabs.length; i++) {
            buttons ~= new SdlButton(
                x,
                cast(int) (y + h - ((i + 1) * h / tabs.length)),
                30,
                cast(int) (h / tabs.length),
                darken(background_color, 0.3f),
                Color(1.0f, 1.0f, 1.0f, 1.0f),
                font,
                "%d".format(i + 1),
                shader,
                (void* user_data) {
                    buttons[active_tab_idx].set_default_color(darken(background_color, 0.3f));
                    active_tab_idx = cast(int) user_data;
                    buttons[active_tab_idx].set_default_color(background_color);
                },
                (void* user_data) {},
                (void* user_data) {},
                cast(void*) i
            );

            this.tabs ~= tabs[i];
        }

        buttons[0].set_default_color(background_color);

        children ~= buttons;
    }

    override void draw() {
        foreach (child; children) {
            child.draw();
        }
        
        tabs[active_tab_idx].draw();
    }

    override void update(int mouse_x, int mouse, int mouse_state, long mouse_wheel) {
        foreach (child; children) {
            child.update(mouse_x, mouse, mouse_state, mouse_wheel);
        }
    }
}