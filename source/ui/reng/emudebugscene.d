module ui.reng.emudebugscene;

import emu.hw.wii;
import re;
import ui.reng.wiivideo;

class EmuDebugInterfaceScene : Scene2D {
    int screen_scale;

    this(int screen_scale) {
        this.screen_scale = screen_scale;
        super();
    }

    override void on_start() {
        auto wii_screen = create_entity("wii_display");
        auto wii_video = wii_screen.add_component(new WiiVideo(screen_scale));
        Core.jar.register(wii_video);

        // add debugger ui
        // auto wii_debugger_ui_nt = create_entity("wii_debugger_nt");
        // wii_debugger_ui_nt.add_component(new WiiDebuggerUIRoot(wii_debugger));
    }

    override void update() {
        super.update();
    }
}