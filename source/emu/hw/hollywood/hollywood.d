module emu.hw.hollywood.hollywood;

import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.log;
import util.number;

final class Hollywood {
    void write_GX_FIFO(T)(T value, int x) {
        log_hollywood("write_GX_FIFO: %08x, %x", value, x);
    }
}