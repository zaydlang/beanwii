module emu.hw.memory.strategy.slowmem.slowmem;

import emu.hw.disk.dol;
import emu.hw.memory.strategy.memstrategy;
import util.log;
import util.number;

final class SlowMem : MemStrategy {
    override public void map_dol(WiiDol* dol, u8[] partition_data) {
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 text_address = cast(u32) dol.text_address[i];
            u32 text_offset  = cast(u32) dol.text_offset[i];
            u32 text_size    = cast(u32) dol.text_size[i];

            log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, text_address, text_offset, text_size);
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 data_address = cast(u32) dol.data_address[i];
            u32 data_offset  = cast(u32) dol.data_offset[i];
            u32 data_size    = cast(u32) dol.data_size[i];

            log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, data_address, data_offset, data_size);
        }

        log_disk("BSS addr: %x", cast(u32) dol.bss_address);
        log_disk("BSS size: %x", cast(u32) dol.bss_size);
        log_disk("Entrypoint: %x", cast(u32) dol.entry_point);
    }
}