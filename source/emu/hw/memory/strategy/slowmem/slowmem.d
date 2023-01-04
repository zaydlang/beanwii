module emu.hw.memory.strategy.slowmem.slowmem;

import emu.hw.disk.dol;
import emu.hw.memory.strategy.memstrategy;
import util.array;
import util.log;
import util.number;

// NOTE: this memstrategy is VERY slow! It's very simplistic, and only
// here for basic testing purposes.
final class SlowMem : MemStrategy {
    struct Mapping {
        u32 address;
        u8[] data;

        public bool in_range(u32 address) {
            return address >= this.address && address < this.address + this.data.length;
        }

        public T read_be(T)(u32 address) {
            assert (this.in_range(address));
            return this.data.read_be!T(address - this.address);
        }

        public void write_be(T)(u32 address, T value) {
            assert (this.in_range(address));
            return this.data.write_be!T(cast(size_t) (address - this.address), value);
        }
    }

    Mapping[] mappings;

    override public void map_dol(WiiDol* dol) {
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 text_address = cast(u32) dol.header.text_address[i];
            u32 text_offset  = cast(u32) dol.header.text_offset[i];
            u32 text_size    = cast(u32) dol.header.text_size[i];

            u32 dol_data_offset = text_offset + cast(u32) WiiDolHeader.sizeof;

            if (text_size == 0) continue;

            log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, text_address, text_offset, text_size);
            mappings ~= Mapping(text_address, dol.data[dol_data_offset .. dol_data_offset + text_size]);

            log_disk("debug: %x = %x", text_offset + 0x2124, cast(u32) dol.data.read_be!u32(text_offset + 0x2124));
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 data_address = cast(u32) dol.header.data_address[i];
            u32 data_offset  = cast(u32) dol.header.data_offset[i];
            u32 data_size    = cast(u32) dol.header.data_size[i];

            u32 dol_data_offset = data_offset + cast(u32) WiiDolHeader.sizeof;

            if (data_size == 0) continue;
            
            log_disk("Mapping data section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, data_address, data_offset, data_size);
            mappings ~= Mapping(data_address, dol.data[dol_data_offset .. dol_data_offset + data_size]);
        }

        u32 bss_address = cast(u32) dol.header.bss_address;
        u32 bss_size    = cast(u32) dol.header.bss_size;

        if (bss_size != 0) {
            log_disk("Mapping BSS at 0x%08X, size 0x%08X", bss_address, bss_size);
            mappings ~= Mapping(cast(u32) dol.header.bss_address, new u8[cast(u32) dol.header.bss_size]);
            for (int i = 0; i < cast(u32) dol.header.bss_size; i++) {
                mappings[$ - 1].write_be!u8(bss_address + i, 0x00);
            }
        }

        log_disk("Entrypoint: %x", cast(u32) dol.header.entry_point);
    }
    
    override public u64 read_be_u64(u32 address) { return read_be!u64(address); }
    override public u32 read_be_u32(u32 address) { return read_be!u32(address); }
    override public u16 read_be_u16(u32 address) { return read_be!u16(address); }
    override public u8  read_be_u8 (u32 address) { return read_be!u8 (address); }

    override public void write_be_u64(u32 address, u64 value) { write_be!u64(address, value); }
    override public void write_be_u32(u32 address, u32 value) { write_be!u32(address, value); }
    override public void write_be_u16(u32 address, u16 value) { write_be!u16(address, value); }
    override public void write_be_u8 (u32 address, u8  value) { write_be!u8 (address, value); }

    private T read_be(T)(u32 address) {
        foreach (mapping; mappings) {
            if (mapping.in_range(address)) {
                return mapping.read_be!T(address);
            }
        }

        error_slowmem("Read from invalid address 0x%08X", address);
        assert (0);
    }

    private void write_be(T)(u32 address, T value) {
        log_jit("Write to 0x%08X: %x", address, value);
        foreach (mapping; mappings) {        
            log_jit("Write to 0x%08X: %x", address, value);
            if (mapping.in_range(address)) {
                mapping.write_be!T(address, value);
                return;
            }
        }

        // error_slowmem("Write to invalid address 0x%08X", address);
        // assert (0);
    }
}