module emu.hw.broadway.cpu;

import emu.hw.broadway.state;
import util.endian;
import util.number;

final class BroadwayCpu {
    private BroadwayState state;

    public void set_pc(u32 pc) {
        state.pc = pc;
    }
}