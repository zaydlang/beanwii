module emu.hw.ipc.usb.extensions.nunchuk;

import emu.hw.ipc.usb.extensions.extension;
import util.number;

struct NunchukState {
    int stick_x;
    int stick_y;
    int accel_x;
    int accel_y;
    int accel_z;
    bool c_pressed;
    bool z_pressed;
}

final class NunchukExtension : WiimoteExtension {
    private NunchukState state;

    this() {
        // Default to centered stick and neutral gravity on Z.
        state = NunchukState(128, 128, 512, 512, 512, false, false);
    }

    void set_state(NunchukState new_state) {
        state = NunchukState(
            clamp(new_state.stick_x, 31, 221),
            clamp(new_state.stick_y, 31, 221),
            clamp(new_state.accel_x, 0, 1023),
            clamp(new_state.accel_y, 0, 1023),
            clamp(new_state.accel_z, 0, 1023),
            new_state.c_pressed,
            new_state.z_pressed
        );
    }

    override u8[6] get_report_data() {
        u16 ax = cast(u16) state.accel_x;
        u16 ay = cast(u16) state.accel_y;
        u16 az = cast(u16) state.accel_z;

        u8 sx = cast(u8) state.stick_x;
        u8 sy = cast(u8) state.stick_y;

        u8 byte2 = cast(u8) ((ax >> 2) & 0xFF);
        u8 byte3 = cast(u8) ((ay >> 2) & 0xFF);
        u8 byte4 = cast(u8) ((az >> 2) & 0xFF);

        u8 ax_low = cast(u8) (ax & 0x3);
        u8 ay_low = cast(u8) (ay & 0x3);
        u8 az_low = cast(u8) (az & 0x3);

        u8 c_bit = cast(u8) (state.c_pressed ? 0 : 1);
        u8 z_bit = cast(u8) (state.z_pressed ? 0 : 1);

        u8 byte5 = cast(u8) (
            (az_low << 6) |
            (ay_low << 4) |
            (ax_low << 2) |
            (c_bit << 1)  |
            (z_bit << 0)
        );

        import std.stdio;
        writefln("sx: %d, sy: %d, ax: %d, ay: %d, az: %d, c: %s, z: %s => bytes: [%02X %02X %02X %02X %02X %02X]",
            sx, sy, ax, ay, az,
            state.c_pressed ? "pressed" : "released",
            state.z_pressed ? "pressed" : "released",
            sx, sy, byte2, byte3, byte4, byte5
        );

        return [sx, sy, byte2, byte3, byte4, byte5];
    }

    override u8[6] get_id() {
        return [0x00, 0x00, 0xA4, 0x20, 0x00, 0x00];
    }

    private int clamp(int value, int min_value, int max_value) {
        if (value < min_value) return min_value;
        if (value > max_value) return max_value;
        return value;
    }
}
