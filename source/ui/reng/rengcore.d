module ui.reng.rengcore;

import emu.hw.wii;
import raylib;
import re;
import re.math;
import std.algorithm.comparison : max;
import ui.device;
import ui.reng.emudebugscene;
import ui.reng.emuscene;

class RengCore : Core {
    int width;
    int height;
    int screen_scale;
    bool start_debugger;
    Wii wii;

    this(Wii wii, int screen_scale, bool start_debugger) {
        this.wii            = wii;
        this.screen_scale   = screen_scale;
        this.start_debugger = start_debugger;

        this.width  = WII_SCREEN_WIDTH * screen_scale;
        this.height = WII_SCREEN_HEIGHT * screen_scale;

        if (this.start_debugger) {
            this.width  = max(this.width,  1280);
            this.height = max(this.height, 720);

        }

        // raylib.SetConfigFlags(raylib.ConfigFlags.FLAG_WINDOW_RESIZABLE);
        super(width, height, "BeanWii");
        sync_render_target_to_window_resolution = true;
    }

    override void initialize() {
        default_resolution = Vector2(width, height);
        content.paths ~= ["../content/", "content/"];

        screen_scale *= cast(int) window.dpi_scale();

        // if (start_debugger) {
            // load_scenes([new EmuDebugInterfaceScene(wii.get_debugger(), screen_scale)]);
        // } else {
            load_scenes([new EmuScene(screen_scale)]);
        // }
    }

    pragma(inline, true) {
        void update_pub() {
            update();
        }

        void draw_pub() {
            draw();
        }
    }
}
