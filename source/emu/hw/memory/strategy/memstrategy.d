module emu.hw.memory.strategy.memstrategy;

import emu.hw.disk.dol;
import emu.hw.memory.strategy.slowmem.slowmem;
import util.number;

alias Mem = SlowMem;

interface MemStrategy {
    public void map_dol(WiiDol* dol, u8[] partition_data);
}
