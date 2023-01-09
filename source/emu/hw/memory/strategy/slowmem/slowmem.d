module emu.hw.memory.strategy.slowmem.slowmem;

import emu.hw.broadway.hle;
import emu.hw.disk.dol;
import emu.hw.memory.strategy.memstrategy;
import util.array;
import util.log;
import util.number;

// NOTE: this memstrategy is VERY slow! It's very simplistic, and only
// here for basic testing purposes.
final class SlowMem : MemStrategy {
    enum MEM1_SIZE = 0x1800000;
    enum MEM2_SIZE = 0x4000000;
    enum HLE_TRAMPOLINE_SIZE = HLE_MAX_FUNCS * 4;

    u8[] mem1;
    u8[] mem2;
    u8[] hle_trampoline;

    this() {
        mem1 = new u8[MEM1_SIZE];
        mem2 = new u8[MEM2_SIZE];
        hle_trampoline = new u8[HLE_TRAMPOLINE_SIZE];
    }

    private T read_be(T)(u32 address) {
        auto region = address >> 28;
        auto offset = address & 0xFFF_FFFF;

        T result;

        switch (region) {
            case 0x8:
            case 0xC:
                assert(offset < MEM1_SIZE);
                result = this.mem1.read_be!T(offset);
                break;
            
            case 0x9:
            case 0xD:
                assert(offset < MEM2_SIZE);
                result = this.mem2.read_be!T(offset);
                break;
            
            case 0x2:
                assert(offset < HLE_TRAMPOLINE_SIZE);
                result = this.hle_trampoline.read_be!T(offset);
                break;
            
            default:
                error_slowmem("Read from invalid address 0x%08X", address);
                assert(0);
        }

        log_slowmem("Read 0x%08x from address 0x%08x", result, address);
        return result;
    }

    private void write_be(T)(u32 address, T value) {
        // log_slowmem("Write 0x%08x to address 0x%08x", value, address);

        auto region = address >> 28;
        auto offset = address & 0xFFF_FFFF;

        switch (region) {
            case 0x8:
            case 0xC:
                assert(offset < MEM1_SIZE);
                return this.mem1.write_be!T(offset, value);
            
            case 0x9:
            case 0xD:
                assert(offset < MEM2_SIZE);
                return this.mem2.write_be!T(offset, value);
            
            case 0x2:
                assert(offset < HLE_TRAMPOLINE_SIZE);
                return this.hle_trampoline.write_be!T(offset, value);
            
            default:
                error_slowmem("Write 0x%08x to invalid address 0x%08X", value, address);
                assert(0);
        }
    }
    
    override public u64 read_be_u64(u32 address) { return read_be!u64(address); }
    override public u32 read_be_u32(u32 address) { return read_be!u32(address); }
    override public u16 read_be_u16(u32 address) { return read_be!u16(address); }
    override public u8  read_be_u8 (u32 address) { return read_be!u8 (address); }

    override public void write_be_u64(u32 address, u64 value) { write_be!u64(address, value); }
    override public void write_be_u32(u32 address, u32 value) { write_be!u32(address, value); }
    override public void write_be_u16(u32 address, u16 value) { write_be!u16(address, value); }
    override public void write_be_u8 (u32 address, u8  value) { write_be!u8 (address, value); }

    override public void map_buffer(u8* buffer, size_t buffer_size, u32 address) {
        for (int i = 0; i < buffer_size; i++) {
            this.write_be!u8(address + i, buffer[i]);
        }
    }

    override public void map_dol(WiiDol* dol) {
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 text_address = cast(u32) dol.header.text_address[i];
            u32 text_offset  = cast(u32) dol.header.text_offset[i];
            u32 text_size    = cast(u32) dol.header.text_size[i];

            u32 dol_data_offset = text_offset - cast(int) WiiDolHeader.sizeof;

            if (text_size == 0) continue;

            log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, text_address, text_offset, text_size);
            map_buffer(&dol.data.ptr[dol_data_offset], text_size, text_address);
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 data_address = cast(u32) dol.header.data_address[i];
            u32 data_offset  = cast(u32) dol.header.data_offset[i];
            u32 data_size    = cast(u32) dol.header.data_size[i];

            u32 dol_data_offset = data_offset - cast(int) WiiDolHeader.sizeof;

            if (data_size == 0) continue;
            
            log_disk("Mapping data section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, data_address, data_offset, data_size);
            map_buffer(&dol.data.ptr[dol_data_offset], data_size, data_address);
        }

        u32 bss_address = cast(u32) dol.header.bss_address;
        u32 bss_size    = cast(u32) dol.header.bss_size;

        if (bss_size != 0) {
            log_disk("Mapping BSS at 0x%08X, size 0x%08X", bss_address, bss_size);
            for (int i = 0; i < cast(u32) dol.header.bss_size; i++) {
                this.write_be!u8(bss_address + i, 0x00);
            }
        }

        log_disk("Entrypoint: %x", cast(u32) dol.header.entry_point);
    }
}