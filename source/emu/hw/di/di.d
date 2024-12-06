module emu.hw.di.di;

import util.bitop;
import util.number;

final class DVDInterface {
    u8 read_DICFG(int target_byte) {
        return target_byte == 0 ? 1 : 0;
    }

    u32 hw_compat;
    u8 read_HW_COMPAT(int target_byte) {
        return hw_compat.get_byte(target_byte);
    }

    void write_HW_COMPAT(int target_byte, u8 value) {
        hw_compat = hw_compat.set_byte(target_byte, value);
    }
}