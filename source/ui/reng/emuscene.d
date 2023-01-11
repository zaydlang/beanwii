module ui.reng.emuscene;

import re;
import ui.reng.wiivideo;

class EmuScene : Scene2D {
    int screen_scale;

    this(int screen_scale) {
        this.screen_scale = screen_scale;
        super();
    }

    override void on_start() {
        auto wii_screen = create_entity("wii_display");
        auto wii_video = wii_screen.add_component(new WiiVideo(screen_scale));
        Core.jar.register(wii_video);
    }

    override void update() {
        super.update();
    }
}