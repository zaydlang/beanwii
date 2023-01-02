module emu.hw.memory.strategy.slowmem.slowmem;

import emu.hw.disk.dol;
import emu.hw.memory.strategy.memstrategy;
import util.log;
import util.number;

// NOTE: this memstrategy is VERY slow! It's very simplistic, and only
// here for basic testing purposes.
final class SlowMem : MemStrategy {
    struct Mapping {
        u32 address;
        u8[] data;
    }

    public bool in_range(Mapping mapping, u32 address) {
        return address >= mapping.address && address < mapping.address + mapping.data.length;
    }

    public T read_be(T)(Mapping mapping, u32 address) {
        assert(mapping.in_range(address));
        return mapping.data.read_be!T(address);
    }

    Mapping[] mappings;

    override public void map_dol(WiiDol* dol, u8[] partition_data) {
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 text_address = cast(u32) dol.text_address[i];
            u32 text_offset  = cast(u32) dol.text_offset[i];
            u32 text_size    = cast(u32) dol.text_size[i];
            mappings ~= Mapping(text_address, partition_data[text_offset .. text_offset + text_size]);

            log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, text_address, text_offset, text_size);
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 data_address = cast(u32) dol.data_address[i];
            u32 data_offset  = cast(u32) dol.data_offset[i];
            u32 data_size    = cast(u32) dol.data_size[i];
            mappings ~= Mapping(data_address, partition_data[data_offset .. data_offset + data_size]);

            log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, data_address, data_offset, data_size);
        }

        log_disk("BSS addr: %x", cast(u32) dol.bss_address);
        log_disk("BSS size: %x", cast(u32) dol.bss_size);
        mappings ~= Mapping(cast(u32) dol.bss_address, new u8[cast(u32) dol.bss_size]);

        log_disk("Entrypoint: %x", cast(u32) dol.entry_point);
    }

    T read_be(T)(u32 address) {
        foreach (mapping; mappings) {
            if (mapping.in_range(address)) {
                return mapping.read_be!T(address);
            }
        }

        error_slowmem("Read from invalid address 0x%08X", address);
    }
}