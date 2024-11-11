module emu.hw.si.si;

import util.bitop;
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

    void write_SICxOUTBUF(int target_byte, u8 value, int x) {
        error_si("Unimplemented: SICxOUTBUF write");
    }

    u32 sipoll;
    
    u8 read_SIPOLL(int target_byte) {
        return sipoll.get_byte(target_byte);
    }

    void write_SIPOLL(int target_byte, u8 value) {
        sipoll = sipoll.set_byte(target_byte, value);
    }

    u32 sicomcsr;

    u8 read_SICOMCSR(int target_byte) {
        return sicomcsr.get_byte(target_byte);
    }

    void write_SICOMCSR(int target_byte, u8 value) {
        sicomcsr = sicomcsr.set_byte(target_byte, value);
    }

    u32 siexilk;

    u8 read_SIEXILK(int target_byte) {
        return siexilk.get_byte(target_byte);
    }

    void write_SIEXILK(int target_byte, u8 value) {
        siexilk = siexilk.set_byte(target_byte, value);
    }

    u32 sisr;

    u8 read_SISR(int target_byte) {
        return sisr.get_byte(target_byte);
    }

    void write_SISR(int target_byte, u8 value) {
        sisr = sisr.set_byte(target_byte, value);
    }

    u32 siobuf;

    u8 read_SIOBUF(int target_byte) {
        return siobuf.get_byte(target_byte);
    }

    void write_SIOBUF(int target_byte, u8 value) {
        siobuf = siobuf.set_byte(target_byte, value);
    }
}
