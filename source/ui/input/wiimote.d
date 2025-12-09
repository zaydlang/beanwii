module ui.input.wiimote;

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
    
    float get_wiimote_roll(wiimote_t* wm);
    float get_wiimote_pitch(wiimote_t* wm);
    float get_wiimote_yaw(wiimote_t* wm);
    
    int get_wiimote_ir_dot_visible(wiimote_t* wm, int dot);
    int get_wiimote_ir_dot_x(wiimote_t* wm, int dot);
    int get_wiimote_ir_dot_y(wiimote_t* wm, int dot);
    int get_wiimote_ir_dot_size(wiimote_t* wm, int dot);
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
}

class HardwareWiimote {
    private {
        wiimote_t** _wiimotes;
        int _count;
        bool _initialized;
    }
    
    this() {
        _wiimotes = wiiuse_init(4);
        _initialized = true;
    }
    
    ~this() {
        if (_initialized && _wiimotes) {
            wiiuse_cleanup(_wiimotes, 4);
        }
    }
    
    int connect(int timeout = 5) {
        if (!_initialized) return 0;
        
        int found = wiiuse_find(_wiimotes, 4, timeout);
        if (found == 0) return 0;
        
        _count = wiiuse_connect(_wiimotes, found);
        
        for (int i = 0; i < _count; i++) {
            wiiuse_set_leds(_wiimotes[i], 0x10 << i);
            wiiuse_set_ir(_wiimotes[i], 1);
            wiiuse_motion_sensing(_wiimotes[i], 1);
        }
        
        return _count;
    }
    
    void disconnect() {
        _count = 0;
    }
    
    bool poll() {
        if (!_initialized || _count == 0) return false;
        return wiiuse_poll(_wiimotes, _count) != 0;
    }
    
    HardwareWiimoteState get_state(int controller_id) {
        if (controller_id < 0 || controller_id >= _count) {
            return HardwareWiimoteState.init;
        }
        
        auto wm = _wiimotes[controller_id];
        HardwareWiimoteState state;
        
        state.buttons = get_wiimote_btns(wm);
        state.buttons_held = get_wiimote_btns_held(wm);
        state.buttons_released = get_wiimote_btns_released(wm);
        
        state.ir_dots = get_wiimote_ir_found(wm);
        state.ir_x = get_wiimote_ir_x(wm);
        state.ir_y = get_wiimote_ir_y(wm);
        state.ir_z = get_wiimote_ir_z(wm);
        
        state.roll = get_wiimote_roll(wm);
        state.pitch = get_wiimote_pitch(wm);
        state.yaw = get_wiimote_yaw(wm);
        
        state.battery = get_wiimote_battery_level(wm);
        state.connected = true;
        
        return state;
    }
    
    bool is_pressed(int controller_id, WiimoteButton button) {
        auto state = get_state(controller_id);
        return (state.buttons_held & button) != 0;
    }
    
    void set_rumble(int controller_id, bool enabled) {
        if (controller_id >= 0 && controller_id < _count) {
            wiiuse_rumble(_wiimotes[controller_id], enabled ? 1 : 0);
        }
    }
    
    @property int count() const {
        return _count;
    }
}

