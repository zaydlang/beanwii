module ui.reng.device;

import raylib;
import re;
import std.format;
import std.string;
import ui.device;
import ui.reng.rengcore;
import ui.reng.wiivideo;

class RengMultimediaDevice : MultiMediaDevice {
    enum SAMPLE_RATE            = 48_000;
    enum SAMPLES_PER_UPDATE     = 4096;
    enum BUFFER_SIZE_MULTIPLIER = 3;
    enum NUM_CHANNELS           = 2;

    enum FAST_FOWARD_KEY        = Keys.KEY_TAB;

    RengCore reng_core;
    WiiVideo  wii_video;
    AudioStream stream;

    bool fast_foward;

    string rom_title;
    int fps;

    this(int screen_scale, bool full_ui) {
        Core.target_fps = 60;
        reng_core = new RengCore(screen_scale, full_ui);

        InitAudioDevice();
        SetAudioStreamBufferSizeDefault(SAMPLES_PER_UPDATE);
        stream = LoadAudioStream(SAMPLE_RATE, 16, NUM_CHANNELS);
        PlayAudioStream(stream);
        
        wii_video = Core.jar.resolve!WiiVideo().get; 
    }

    override {
        // video stuffs
        void present_videobuffer(VideoBuffer buffer) {
            for (int y = 0; y < WII_SCREEN_HEIGHT; y++) {
            for (int x = 0; x < WII_SCREEN_WIDTH;  x++) {
                    wii_video.videobuffer[y * WII_SCREEN_WIDTH + x] = 
                        (buffer[x][y].r <<  0) |
                        (buffer[x][y].g <<  8) |
                        (buffer[x][y].b << 16) |
                        0xFF000000;
            }
            }
        }

        void set_fps(int fps) {
            this.fps = fps;
            redraw_title();
        }

        void update_rom_title(string rom_title) {
            import std.string;
            this.rom_title = rom_title.splitLines[0].strip;
            redraw_title();
        }

        void update_icon(Pixel[32][32] buffer_texture) {
            import std.stdio;

            uint[32 * 32] icon_texture;

            for (int x = 0; x < 32; x++) {
            for (int y = 0; y < 32; y++) {
                icon_texture[y * 32 + x] = 
                    (buffer_texture[x][y].r <<  0) |
                    (buffer_texture[x][y].g <<  8) |
                    (buffer_texture[x][y].b << 16) |
                    0xFF000000;
            }
            }

            wii_video.update_icon(icon_texture);
        }

        // 2 cuz stereo
        short[NUM_CHANNELS * SAMPLES_PER_UPDATE * BUFFER_SIZE_MULTIPLIER] buffer;
        int buffer_cursor = 0;

        void push_sample(Sample s) {
            buffer[buffer_cursor + 0] = s.L;
            buffer[buffer_cursor + 1] = s.R;
            buffer_cursor += 2;
        }

        void update() {
            handle_input();
            handle_audio();
            reng_core.update_pub();
        }

        void draw() {
            reng_core.draw_pub();
        }

        void handle_input() {
            // TODO
        }

        bool should_fast_forward() {
            return fast_foward;
        }
    }

    void redraw_title() {
        import std.format;
        wii_video.update_title("%s [FPS: %d]".format(rom_title, fps));
    }

    void handle_audio() {
        if (IsAudioStreamProcessed(stream)) {
            UpdateAudioStream(stream, cast(void*) buffer, SAMPLES_PER_UPDATE);
            
            for (int i = 0; i < NUM_CHANNELS * SAMPLES_PER_UPDATE * (BUFFER_SIZE_MULTIPLIER - 1); i++) {
                buffer[i] = buffer[i + NUM_CHANNELS * SAMPLES_PER_UPDATE];
            }

            buffer_cursor -= NUM_CHANNELS * SAMPLES_PER_UPDATE;
            if (buffer_cursor < 0) buffer_cursor = 0;

            if (fast_foward) buffer_cursor = 0;
        }
    }
}