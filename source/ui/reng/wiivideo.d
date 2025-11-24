module ui.reng.wiivideo;

import bindbc.opengl;
import raylib;
import re;
import re.gfx;
import re.math;
import rlgl;
import std.format;
import std.string;
import ui.device;
import util.log;

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

        // loadOpenGL();
        // GLuint[1] texture;
        // glGenTextures(1, texture.ptr);
        // glBindTexture(GL_TEXTURE_2D, texture[0]);
        // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        // GLuint[1] fb;
        // glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 256, 256, 0, GL_BGRA, GL_UNSIGNED_BYTE, null);
        
        // auto shitlord = rlLoadFramebuffer(WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);
            // glGenFramebuffers(1, fb.ptr);
        // rlEnableFramebuffer(shitlord);
        // rlFramebufferAttach(shitlord, render_target_screen.texture.id, 0, RL_ATTACHMENT_TEXTURE2D, 0);
            // glBindFramebuffer(GL_FRAMEBUFFER, fb[0]);
        // glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture[0], 0);

        // GLuint depth_rb;
        // glGenRenderbuffers(1, &depth_rb);
        // glBindRenderbuffer(GL_RENDERBUFFER, depth_rb);
        // glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, 256, 256);

        // glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth_rb);
        
        // GLenum status;
        // status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        // if (status != GL_FRAMEBUFFER_COMPLETE) {
        //     error_frontend("fuck");
        // }

        // glBindFramebuffer(GL_FRAMEBUFFER, fb[0]);
        // glClearColor(0.0, 0.0, 0.0, 0.0);
        // glClearDepth(1.0f);
        // glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        // glViewport(0, 0, 256, 256);
        // glDisable(GL_TEXTURE_2D);
        // glDisable(GL_BLEND);
        // glEnable(GL_DEPTH_TEST);
        // glBindFramebuffer(GL_FRAMEBUFFER, 0);

        // glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

        rlBegin(GL_TRIANGLES);
            rlVertex2f(-50, -50);
            rlVertex2f(50, -50);
            rlVertex2f(0, 50);
        rlEnd();
        
        UpdateTexture(render_target_screen.texture, cast(const void*) videobuffer);

        // raylib.DrawTexturePro(
        //     render_target_screen.texture,
        //     Rectangle(0, 0, WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT),
        //     Rectangle(0, 0, WII_SCREEN_WIDTH * screen_scale, WII_SCREEN_HEIGHT * screen_scale),
        //     Vector2(0, 0),
        //     0,
        //     Colors.WHITE
        // );

        
    }

    void debug_render() {
        raylib.DrawRectangleLinesEx(bounds, 1, Colors.RED);
    }

    @property Rectangle bounds() {
        return Rectangle(0, 0, WII_SCREEN_WIDTH * screen_scale, WII_SCREEN_HEIGHT * screen_scale);
    }
}