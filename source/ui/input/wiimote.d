module ui.input.wiimote;

import core.atomic;
import core.sync.mutex;
import core.thread;
import core.time;

extern(C) {
    struct wiimote_t;
    
    const(char)* wiiuse_version();
    wiimote_t** wiiuse_init(int wiimotes);
    int wiiuse_find(wiimote_t** wm, int max_wiimotes, int timeout);
    int wiiuse_connect(wiimote_t** wm, int wiimotes);
    int wiiuse_poll(wiimote_t** wm, int wiimotes);
    void wiiuse_cleanup(wiimote_t** wm, int wiimotes);
    void wiiuse_set_leds(wiimote_t* wm, int leds);
    void wiiuse_rumble(wiimote_t* wm, int status);
    void wiiuse_set_ir(wiimote_t* wm, int status);
    void wiiuse_motion_sensing(wiimote_t* wm, int status);
    
    int get_wiimote_unid(wiimote_t* wm);
    ushort get_wiimote_btns(wiimote_t* wm);
    ushort get_wiimote_btns_held(wiimote_t* wm);
    ushort get_wiimote_btns_released(wiimote_t* wm);
    float get_wiimote_battery_level(wiimote_t* wm);
    
    int get_wiimote_ir_found(wiimote_t* wm);
    int get_wiimote_ir_x(wiimote_t* wm);
    int get_wiimote_ir_y(wiimote_t* wm);
    float get_wiimote_ir_z(wiimote_t* wm);
    
    ubyte get_wiimote_accel_x(wiimote_t* wm);
    ubyte get_wiimote_accel_y(wiimote_t* wm);
    ubyte get_wiimote_accel_z(wiimote_t* wm);

    float get_wiimote_roll(wiimote_t* wm);
    float get_wiimote_pitch(wiimote_t* wm);
    float get_wiimote_yaw(wiimote_t* wm);
    int get_wiimote_event(wiimote_t* wm);
    
    int get_wiimote_ir_dot_visible(wiimote_t* wm, int dot);
    int get_wiimote_ir_dot_x(wiimote_t* wm, int dot);
    int get_wiimote_ir_dot_y(wiimote_t* wm, int dot);
    int get_wiimote_ir_dot_size(wiimote_t* wm, int dot);

    int get_wiimote_expansion_type(wiimote_t* wm);
    ubyte get_nunchuk_stick_x_raw(wiimote_t* wm);
    ubyte get_nunchuk_stick_y_raw(wiimote_t* wm);
    ubyte get_nunchuk_accel_x(wiimote_t* wm);
    ubyte get_nunchuk_accel_y(wiimote_t* wm);
    ubyte get_nunchuk_accel_z(wiimote_t* wm);
    int get_nunchuk_button_c(wiimote_t* wm);
    int get_nunchuk_button_z(wiimote_t* wm);
    int get_exp_nunchuk();
}

private enum WiimoteButton : ushort {
    A      = 0x0008,
    B      = 0x0004,
    One    = 0x0002,
    Two    = 0x0001,
    Plus   = 0x1000,
    Minus  = 0x0010,
    Home   = 0x0080,
    Up     = 0x0800,
    Down   = 0x0400,
    Left   = 0x0100,
    Right  = 0x0200,
}

private enum {
    WIIUSE_NONE = 0,
    WIIUSE_EVENT = 1,
    WIIUSE_STATUS = 2,
    WIIUSE_DISCONNECT = 4,
    WIIUSE_UNEXPECTED_DISCONNECT = 5
}

struct HardwareWiimoteState {
    ushort buttons;
    ushort buttons_held;
    ushort buttons_released;
    
    int ir_x, ir_y;
    float ir_z;
    int ir_dots;
    
    float roll, pitch, yaw;
    float battery;
    bool connected;

    // Raw accelerometer readings
    ubyte accel_x;
    ubyte accel_y;
    ubyte accel_z;

    // Nunchuk (raw readings)
    bool has_nunchuk;
    ubyte nunchuk_stick_x;
    ubyte nunchuk_stick_y;
    ubyte nunchuk_accel_x;
    ubyte nunchuk_accel_y;
    ubyte nunchuk_accel_z;
    bool nunchuk_c;
    bool nunchuk_z;
}

final class HardwareWiimote {
    private {
        enum MAX_WIIMOTES = 4;

        wiimote_t** _wiimotes;
        Thread _pollThread;
        Mutex _stateLock;

        HardwareWiimoteState[MAX_WIIMOTES] _latestStates;

        shared bool _running;
        shared bool _connectRequested;
        shared int _count;
        int _timeoutSeconds;
    }
    
    this(int timeoutSeconds = 5) {
        _timeoutSeconds = timeoutSeconds;
        _wiimotes = wiiuse_init(MAX_WIIMOTES);
        _stateLock = new Mutex();

        if (_wiimotes is null) {
            _running = false;
            _connectRequested = false;
            _count = 0;
            return;
        }

        _running = true;
        _connectRequested = true;
        _count = 0;

        _pollThread = new Thread(&this.pollLoop);
        _pollThread.start();
    }
    
    ~this() {
        atomicStore(_running, false);
        if (_pollThread !is null) {
            _pollThread.join();
        }

        if (_wiimotes) {
            wiiuse_cleanup(_wiimotes, MAX_WIIMOTES);
        }
    }
    
    int connect(int timeout = 5) {
        _timeoutSeconds = timeout;
        atomicStore(_connectRequested, true);
        return atomicLoad(_count);
    }
    
    void disconnect() {
        atomicStore(_count, 0);
        atomicStore(_connectRequested, false);

        synchronized (_stateLock) {
            foreach (ref state; _latestStates) {
                state = HardwareWiimoteState.init;
            }
        }
    }
    
    HardwareWiimoteState get_state(int controller_id) {
        if (controller_id < 0 || controller_id >= MAX_WIIMOTES) {
            return HardwareWiimoteState.init;
        }

        synchronized (_stateLock) {
            if (controller_id >= atomicLoad(_count)) {
                return HardwareWiimoteState.init;
            }
            return _latestStates[controller_id];
        }
    }
    
    ushort poll_buttons(int controller_id) {
        return get_state(controller_id).buttons;
    }
    
    bool is_pressed(int controller_id, WiimoteButton button) {
        auto state = get_state(controller_id);
        return (state.buttons_held & button) != 0;
    }
    
    void set_rumble(int controller_id, bool enabled) {
        int count = atomicLoad(_count);
        if (controller_id >= 0 && controller_id < count) {
            wiiuse_rumble(_wiimotes[controller_id], enabled ? 1 : 0);
        }
    }
    
    @property int count() const {
        return atomicLoad(_count);
    }

    private void pollLoop() {
        while (atomicLoad(_running)) {
            int connected_now = atomicLoad(_count);

            if (atomicLoad(_connectRequested) && _wiimotes !is null && connected_now < MAX_WIIMOTES) {
                int available_slots = MAX_WIIMOTES - connected_now;
                int find_timeout = connected_now > 0 ? 0 : _timeoutSeconds;
                int found = wiiuse_find(_wiimotes + connected_now, available_slots, find_timeout);
                if (found > 0) {
                    int connected = wiiuse_connect(_wiimotes + connected_now, found);
                    if (connected > 0) {
                        int new_total = connected_now + connected;
                        atomicStore(_count, new_total);
                        for (int i = connected_now; i < new_total && i < MAX_WIIMOTES; i++) {
                            wiiuse_set_leds(_wiimotes[i], 0x10 << i);
                            wiiuse_set_ir(_wiimotes[i], 1);
                            wiiuse_motion_sensing(_wiimotes[i], 1);
                        }
                    }
                }

                atomicStore(_connectRequested, false);

                Thread.sleep(msecs(50));
                connected_now = atomicLoad(_count);
            }

            if (connected_now > 0 && wiiuse_poll(_wiimotes, connected_now)) {
                synchronized (_stateLock) {
                    for (int i = 0; i < connected_now && i < MAX_WIIMOTES; i++) {
                        auto wm = _wiimotes[i];
                        int event = get_wiimote_event(wm);

                        if (event == WIIUSE_DISCONNECT || event == WIIUSE_UNEXPECTED_DISCONNECT) {
                            atomicStore(_count, 0);
                            foreach (ref state; _latestStates) {
                                state = HardwareWiimoteState.init;
                            }
                            atomicStore(_connectRequested, true);
                            break;
                        }

                        auto state = &_latestStates[i];
                        state.buttons = get_wiimote_btns(wm);
                        state.buttons_held = get_wiimote_btns_held(wm);
                        state.buttons_released = get_wiimote_btns_released(wm);
                        
                        state.ir_dots = get_wiimote_ir_found(wm);
                        state.ir_x = get_wiimote_ir_x(wm);
                        state.ir_y = get_wiimote_ir_y(wm);
                        state.ir_z = get_wiimote_ir_z(wm);
                        
                        state.accel_x = get_wiimote_accel_x(wm);
                        state.accel_y = get_wiimote_accel_y(wm);
                        state.accel_z = get_wiimote_accel_z(wm);

                        state.roll = get_wiimote_roll(wm);
                        state.pitch = get_wiimote_pitch(wm);
                        state.yaw = get_wiimote_yaw(wm);
                        
                        state.battery = get_wiimote_battery_level(wm);
                        state.connected = true;

                        state.has_nunchuk = get_wiimote_expansion_type(wm) == get_exp_nunchuk();
                        if (state.has_nunchuk) {
                            state.nunchuk_stick_x = get_nunchuk_stick_x_raw(wm);
                            state.nunchuk_stick_y = get_nunchuk_stick_y_raw(wm);
                            state.nunchuk_accel_x = get_nunchuk_accel_x(wm);
                            state.nunchuk_accel_y = get_nunchuk_accel_y(wm);
                            state.nunchuk_accel_z = get_nunchuk_accel_z(wm);
                            state.nunchuk_c = get_nunchuk_button_c(wm) != 0;
                            state.nunchuk_z = get_nunchuk_button_z(wm) != 0;
                        } else {
                            state.nunchuk_stick_x = 0;
                            state.nunchuk_stick_y = 0;
                            state.nunchuk_accel_x = 0;
                            state.nunchuk_accel_y = 0;
                            state.nunchuk_accel_z = 0;
                            state.nunchuk_c = false;
                            state.nunchuk_z = false;
                        }
                    }
                }
            }

            Thread.sleep(msecs(5));
        }
    }
}
