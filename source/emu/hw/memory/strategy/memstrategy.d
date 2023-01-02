module emu.hw.memory.strategy.memstrategy;

import emu.hw.disk.dol;
import util.number;

interface MemStrategy {
    public void map_dol(WiiDol* dol, u8[] partition_data);
}
