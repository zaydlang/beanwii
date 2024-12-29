module ui.runner;

import core.sync.mutex;
import emu.hw.wii;
import raylib;
import std.datetime.stopwatch;
import ui.device;

final class Runner {
    Wii wii;
    bool fast_forward;

    Mutex should_cycle_wii_mutex;
    bool should_cycle_wii;

    MultiMediaDevice frontend;

    size_t sync_to_audio_lower;
    size_t sync_to_audio_upper;

    StopWatch stopwatch;

    bool running;
    int fps = 0;

    this(Wii wii, MultiMediaDevice frontend) {
        this.wii = wii;

        this.should_cycle_wii_mutex = new Mutex();

        this.frontend = frontend;

        this.should_cycle_wii = true;
        this.running          = true;
    }

    void tick() {
        fps++;
        
        if (stopwatch.peek.total!"msecs" > 1000) {
            frontend.set_fps(fps);
            stopwatch.reset();
            fps = 0;
        }

        frontend.update();
        frontend.draw();
    }

    void run() {
        stopwatch = StopWatch(AutoStart.yes);

        while (running) {
            wii.cycle(33_513_982 / 60);
            tick();
        }
}
}   