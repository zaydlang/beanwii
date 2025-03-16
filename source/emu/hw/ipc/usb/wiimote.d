module emu.hw.ipc.usb.wiimote;

enum WiimoteState {
    Disconnected,
    Connecting,
    Connected,
}

final class Wiimote {
    WiimoteState state;

    this() {
        state = WiimoteState.Disconnected;
    }

    void start_connecting() {
        state = WiimoteState.Connecting;   
    }

    void finish_connecting() {
        state = WiimoteState.Connected;
    }

    bool is_connecting() {
        return state == WiimoteState.Connecting;
    }

    bool is_connected() {
        return state == WiimoteState.Connected;
    }

    bool is_disconnected() {
        return state == WiimoteState.Disconnected;
    }
}