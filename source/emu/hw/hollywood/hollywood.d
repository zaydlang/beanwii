module emu.hw.hollywood.hollywood;

import ui.device;
import util.log;

final class Hollywood {
    private PresentVideoBufferCallback present_videobuffer_callback;
    private VideoBuffer video_buffer;

    public void set_present_videobuffer_callback(PresentVideoBufferCallback callback) {
        this.present_videobuffer_callback = callback;
    }

    public void test() {
        for (int x = 0; x < WII_SCREEN_WIDTH; x++) {
        for (int y = 0; y < WII_SCREEN_HEIGHT; y++) {
            video_buffer[x][y].r = 0;
            video_buffer[x][y].g = 0;
            video_buffer[x][y].b = 0xFF;
        }
        }

        log_hollywood("presenting videobuffer...");

        this.present_videobuffer_callback(video_buffer);
    }
}