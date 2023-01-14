module emu.hw.si.si;

import util.log;
import util.number;

final class SerialInterface {
    // Apparently the Serial Interface is only used for GameCube controllers.
    // I really don't care about emulating those. But the Apploader does poke
    // a couple of its MMIO registers, so I'm going to stub the bare minimum.

    // For more details, see __OSPADButton at https://wiibrew.org/wiki/Memory_map

    u8 read_SICxOUTBUF(int target_byte, int x) {
        assert (x == 3);
        return 0;
    }

    void write_SICxOUTBUF(int target_byte, int x, u8 value) {
        error_si("Unimplemented: SICxOUTBUF write");
    }

    u8 read_SIPOLL(int target_byte) {
        return 0;
    }

    void write_SIPOLL(int target_byte, u8 value) {
        error_si("Unimplemented: SIPOLL write");
    }
}
