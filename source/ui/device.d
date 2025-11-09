module ui.device;

struct Sample {
    short L;
    short R;
}

struct Pixel {
    int r;
    int g;
    int b;
}

enum WII_SCREEN_WIDTH = 864;
enum WII_SCREEN_HEIGHT = 600;

alias VideoBuffer = Pixel[WII_SCREEN_HEIGHT][WII_SCREEN_WIDTH];

alias PresentVideoBufferCallback = void delegate(VideoBuffer* buffer);

abstract class MultiMediaDevice {
    abstract {
        void update();
        void draw();
        void update_rom_title(string title);

        // video stuffs
        void present_videobuffer(VideoBuffer* buffer);
        void set_fps(int fps);
        void update_icon(Pixel[32][32] texture);

        // audio stuffs
        void push_sample(Sample s);
        int get_audio_buffer_capacity();
        int get_audio_buffer_num_samples();

        // input stuffs
        void handle_input();

        bool should_exit();

        bool is_running();
    }

    bool should_fast_forward();
}