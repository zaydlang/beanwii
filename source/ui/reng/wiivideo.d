module ui.reng.wiivideo;

import raylib;
import re;
import re.gfx;
import re.math;
import std.format;
import std.string;
import ui.device;

class WiiVideo : Component, Updatable, Renderable2D {
    int screen_scale;

    RenderTarget render_target_screen;
    RenderTarget render_target_icon;

    uint[WII_SCREEN_WIDTH * WII_SCREEN_HEIGHT] videobuffer;

    this(int screen_scale) {
        this.screen_scale = screen_scale;

        render_target_screen = RenderExt.create_render_target(
            WII_SCREEN_WIDTH,
            WII_SCREEN_HEIGHT
        );

        render_target_icon = RenderExt.create_render_target(
            32,
            32
        );
    }

    override void setup() {

    }

    void update() {

    }

    void update_icon(uint[32 * 32] icon_bitmap) {
        render_target_icon.texture.format = PixelFormat.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
        UpdateTexture(render_target_icon.texture, cast(const void*) icon_bitmap);
        Image image = LoadImageFromTexture(render_target_icon.texture);
        image.format = PixelFormat.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
        SetWindowIcon(image);
    }
    
    void update_title(string title) {
        SetWindowTitle(toStringz(title));
    }

    void render() {
        UpdateTexture(render_target_screen.texture, cast(const void*) videobuffer);

        import std.stdio;
        writefln("rendering video buffer %x %x", videobuffer[0], screen_scale);
        raylib.DrawTexturePro(
            render_target_screen.texture,
            Rectangle(0, 0, WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT),
            Rectangle(0, 0, WII_SCREEN_WIDTH * screen_scale, WII_SCREEN_HEIGHT * screen_scale),
            Vector2(0, 0),
            0,
            Colors.WHITE
        );
    }

    void debug_render() {
        raylib.DrawRectangleLinesEx(bounds, 1, Colors.RED);
    }

    @property Rectangle bounds() {
        return Rectangle(0, 0, WII_SCREEN_WIDTH * screen_scale, WII_SCREEN_HEIGHT * screen_scale);
    }
}