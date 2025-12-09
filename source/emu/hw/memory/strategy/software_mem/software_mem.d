module emu.hw.memory.strategy.software_mem.software_mem;

import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.cp.cp;
import emu.hw.dsp.dsp;
import emu.hw.broadway.cpu;
import emu.hw.disk.dol;
import emu.hw.hollywood.hollywood;
import emu.hw.memory.spec;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.memory.strategy.software_mem.mmio_spec;
import emu.hw.ai.ai;
import emu.hw.di.di;
import emu.hw.exi.exi;
import emu.hw.ipc.ipc;
import emu.hw.pe.pe;
import emu.hw.si.si;
import emu.hw.vi.vi;
import util.array;
import util.bitop;
import util.log;
import util.number;

final class SoftwareMem  {
    enum HLE_TRAMPOLINE_SIZE = HLE_MAX_FUNCS * 4;

    enum MemoryRegion {
        MEM1,
        MEM2,
        HLE_TRAMPOLINE,
        HOLLYWOOD_MMIO,
        BROADWAY_MMIO,
        EXI_BOOT_CODE,
        LOCKED_L2_CACHE,
        EFB,
    }

    struct MemoryAccess {
        MemoryRegion region;
        u32 offset;
    }

    // TODO: temporary public
    public u8[] mem1;
    public u8[] mem2;
    public u8[] hle_trampoline;
    public u8[] locked_l2_cache;

    public Mmio mmio;
    public Broadway cpu;
    
    this() {
        this.mem1 = new u8[MEM1_SIZE];
        this.mem2 = new u8[MEM2_SIZE];
        this.hle_trampoline = new u8[HLE_TRAMPOLINE_SIZE];
        this.locked_l2_cache = new u8[0x40000];
        this.mmio = new Mmio();

        this.mmio.connect_memory(this);
    }

    private MemoryAccess resolve_physical_address(u32 address) {
        if        (0x00000000 <= address && address <= 0x017FFFFF) {
            return MemoryAccess(MemoryRegion.MEM1, address);
        } else if (0x10000000 <= address && address <= 0x13FFFFFF) {
            return MemoryAccess(MemoryRegion.MEM2, address - 0x10000000);
        } else if (0x08000000 <= address && address <= 0x08FFFFFF) {
            return MemoryAccess(MemoryRegion.EFB, address - 0x08000000);
        } else if (0x0D000000 <= address && address <= 0x0D008000) {
            return MemoryAccess(MemoryRegion.HOLLYWOOD_MMIO, address & 0x7FFF);
        } else if (0x0C000000 <= address && address <= 0x0C008003) {
            return MemoryAccess(MemoryRegion.BROADWAY_MMIO, address & 0x7FFF);
        } else if (0xE0000000 <= address && address <= 0xE0040000) {
            return MemoryAccess(MemoryRegion.LOCKED_L2_CACHE, address & 0x3FFFF);
        } else if (0xFFF00100 <= address && address <= 0xFFF0013F) {
            return MemoryAccess(MemoryRegion.EXI_BOOT_CODE, address & 0x3F);
        } else {
            error_memory("Invalid address 0x%08x", address);
            assert(0);
        }
    }

    private MemoryAccess resolve_cpu_address(u32 address) {
        bool real_mode = this.cpu.state.msr.bits(4, 5) != 0b11;

        if (!real_mode) {
            // See: wii.setup_global_memory_value(u8[] wii_disk_data);

            if        (0x80000000 <= address && address <= 0x817FFFFF) {
                return MemoryAccess(MemoryRegion.MEM1, address - 0x80000000);
            } else if (0x90000000 <= address && address <= 0x93FFFFFF) {
                return MemoryAccess(MemoryRegion.MEM2, address - 0x90000000);
            } else if (0xC8000000 <= address && address <= 0xC8FFFFFF) {
                return MemoryAccess(MemoryRegion.EFB, address - 0xC8400000);
            } else if (0xC0000000 <= address && address <= 0xC17FFFFF) {
                return MemoryAccess(MemoryRegion.MEM1, address - 0xC0000000);
            } else if (0xD0000000 <= address && address <= 0xD3FFFFFF) {
                return MemoryAccess(MemoryRegion.MEM2, address - 0xD0000000);
            } else if (0xCC000000 <= address && address <= 0xCDFFFFFF) {
                return MemoryAccess(MemoryRegion.HOLLYWOOD_MMIO, address & 0x7FFF);
            } else if (0xE0000000 <= address && address <= 0xE0040000) {
                return MemoryAccess(MemoryRegion.LOCKED_L2_CACHE, address & 0x3FFFF);
            } else if (0x20000000 <= address && address <= 0x2FFFFFFF) {
                return MemoryAccess(MemoryRegion.HLE_TRAMPOLINE, address - 0x20000000);
            } else {
                error_memory("Invalid address 0x%08x", address);
                assert(0);
            }
        } else {
            return resolve_physical_address(address);
        }
    }

    private T read_memory(T)(MemoryAccess memory_access, u32 original_address) {
        auto region = memory_access.region;
        T result;

        final switch (region) {
            case MemoryRegion.MEM1:
                result = this.mem1.read_be!(T)(memory_access.offset);
                break;
            
            case MemoryRegion.MEM2:
                result = this.mem2.read_be!(T)(memory_access.offset);
                break;
            
            case MemoryRegion.HLE_TRAMPOLINE:
                result = this.hle_trampoline.read_be!(T)(memory_access.offset);
                break;
            
            case MemoryRegion.HOLLYWOOD_MMIO:
                result = this.mmio.read!T(original_address);
                break;

            case MemoryRegion.BROADWAY_MMIO:
                result = this.mmio.read!T(original_address);
                break;

            case MemoryRegion.EXI_BOOT_CODE:
                error_memory("Read from EXI boot code at 0x%08x", original_address);
                break;
            
            case MemoryRegion.LOCKED_L2_CACHE:
                result = this.locked_l2_cache.read_be!(T)(memory_access.offset);
                break;

            case MemoryRegion.EFB:
                result = 0;
                break;
        }

        return result;
    }

    private T cpu_read(T)(u32 address) {
        auto memory_access = resolve_cpu_address(address);
        return read_memory!T(memory_access, address);
    }

    private T physical_read(T)(u32 address) {
        auto memory_access = resolve_physical_address(address);
        return read_memory!T(memory_access, address);
    }

    private void write_memory(T)(MemoryAccess memory_access, u32 original_address, T value) {
        auto region = memory_access.region;

        final switch (region) {
            case MemoryRegion.MEM1:
                this.mem1.write_be!(T)(memory_access.offset, value);
                break;
            
            case MemoryRegion.MEM2:
                this.mem2.write_be!(T)(memory_access.offset, value);
                break;
            
            case MemoryRegion.HLE_TRAMPOLINE:
                this.hle_trampoline.write_be!(T)(memory_access.offset, value);
                break;
            
            case MemoryRegion.HOLLYWOOD_MMIO:
                this.mmio.write!T(original_address, value);
                break;

            case MemoryRegion.BROADWAY_MMIO:
                this.mmio.write!T(original_address, value);
                break;

            case MemoryRegion.EXI_BOOT_CODE:
                error_memory("Write to EXI boot code at 0x%08x", original_address);
                break;

            case MemoryRegion.LOCKED_L2_CACHE:
                this.locked_l2_cache.write_be!(T)(memory_access.offset, value);
                break;

            case MemoryRegion.EFB:
                break;
        }
    }

    private void cpu_write(T)(u32 address, T value) {
        foreach (logged_write; logged_writes) {
            if (address == logged_write) {
                import std.stdio;
                writefln("  Write to 0x%08x = 0x%08x (pc: %x, lr: %x)", address, value, cpu.state.pc, cpu.state.lr);
            }
        }

        auto memory_access = resolve_cpu_address(address);
        write_memory!T(memory_access, address, value);
    }

    private void physical_write(T)(u32 address, T value) {
        auto memory_access = resolve_physical_address(address);
        write_memory!T(memory_access, address, value);
    }

    pragma(inline, true) public u64 cpu_read_physical_u64(u32 address) { return cpu_read!u64(address); }
    pragma(inline, true) public u32 cpu_read_physical_u32(u32 address) { return cpu_read!u32(address); }
    pragma(inline, true) public u16 cpu_read_physical_u16(u32 address) { return cpu_read!u16(address); }
    pragma(inline, true) public u8  cpu_read_physical_u8 (u32 address) { return cpu_read!u8 (address); }

    pragma(inline, true) public void cpu_write_physical_u64(u32 address, u64 value) { cpu_write!u64(address, value); }
    pragma(inline, true) public void cpu_write_physical_u32(u32 address, u32 value) { cpu_write!u32(address, value); }
    pragma(inline, true) public void cpu_write_physical_u16(u32 address, u16 value) { cpu_write!u16(address, value); }
    pragma(inline, true) public void cpu_write_physical_u8 (u32 address, u8 value)  { cpu_write!u8 (address, value); }

    pragma(inline, true) public u64 cpu_read_virtual_u64(u32 address) { return cpu_read!u64(address); }
    pragma(inline, true) public u32 cpu_read_virtual_u32(u32 address) { return cpu_read!u32(address); }
    pragma(inline, true) public u16 cpu_read_virtual_u16(u32 address) { return cpu_read!u16(address); }
    pragma(inline, true) public u8  cpu_read_virtual_u8 (u32 address) { return cpu_read!u8 (address); }

    pragma(inline, true) public void cpu_write_virtual_u64(u32 address, u64 value) { cpu_write!u64(address, value); }
    pragma(inline, true) public void cpu_write_virtual_u32(u32 address, u32 value) { cpu_write!u32(address, value); }
    pragma(inline, true) public void cpu_write_virtual_u16(u32 address, u16 value) { cpu_write!u16(address, value); }
    pragma(inline, true) public void cpu_write_virtual_u8 (u32 address, u8 value)  { cpu_write!u8 (address, value); }

    pragma(inline, true) public u64 cpu_read_u64(u32 address) { return cpu_read!u64(address); }
    pragma(inline, true) public u32 cpu_read_u32(u32 address) { return cpu_read!u32(address); }
    pragma(inline, true) public u16 cpu_read_u16(u32 address) { return cpu_read!u16(address); }
    pragma(inline, true) public u8  cpu_read_u8 (u32 address) { return cpu_read!u8 (address); }

    pragma(inline, true) public void cpu_write_u64(u32 address, u64 value) { cpu_write!u64(address, value); }
    pragma(inline, true) public void cpu_write_u32(u32 address, u32 value) { cpu_write!u32(address, value); }
    pragma(inline, true) public void cpu_write_u16(u32 address, u16 value) { cpu_write!u16(address, value); }
    pragma(inline, true) public void cpu_write_u8 (u32 address, u8 value)  { cpu_write!u8 (address, value); }

    pragma(inline, true) public u8 physical_read_u8(u32 address) {
        return this.physical_read!u8(address);
    }

    pragma(inline, true) public u16 physical_read_u16(u32 address) {
        return this.physical_read!u16(address);
    }

    pragma(inline, true) public u32 physical_read_u32(u32 address) {
        return this.physical_read!u32(address);
    }

    pragma(inline, true) public u64 physical_read_u64(u32 address) {
        return this.physical_read!u64(address);
    }

    pragma(inline, true) public void physical_write_u8(u32 address, u8 value) {
        this.physical_write!u8(address, value);
    }

    pragma(inline, true) public void physical_write_u16(u32 address, u16 value) {
        this.physical_write!u16(address, value);
    }

    pragma(inline, true) public void physical_write_u32(u32 address, u32 value) {
        this.physical_write!u32(address, value);
    }

    pragma(inline, true) public void physical_write_u64(u32 address, u64 value) {
        this.physical_write!u64(address, value);
    }

    public void map_buffer(u8* buffer, size_t buffer_size, u32 address) {
        for (int i = 0; i < buffer_size; i++) {
            this.cpu_write!u8(address + i, buffer[i]);
        }
    }

    public void map_dol(WiiDol* dol) {
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 text_address = cast(u32) dol.header.text_address[i];
            u32 text_offset  = cast(u32) dol.header.text_offset[i];
            u32 text_size    = cast(u32) dol.header.text_size[i];

            u32 dol_data_offset = text_offset - cast(int) WiiDolHeader.sizeof;

            if (text_size == 0) continue;

            map_buffer(&dol.data.ptr[dol_data_offset], text_size, text_address);
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 data_address = cast(u32) dol.header.data_address[i];
            u32 data_offset  = cast(u32) dol.header.data_offset[i];
            u32 data_size    = cast(u32) dol.header.data_size[i];

            u32 dol_data_offset = data_offset - cast(int) WiiDolHeader.sizeof;

            if (data_size == 0) continue;
            
            map_buffer(&dol.data.ptr[dol_data_offset], data_size, data_address);
        }

        u32 bss_address = cast(u32) dol.header.bss_address;
        u32 bss_size    = cast(u32) dol.header.bss_size;

        if (bss_size != 0) {
            for (int i = 0; i < cast(u32) dol.header.bss_size; i++) {
                this.cpu_write!u8(bss_address + i, 0x00);
            }
        }
    }

    public void connect_audio_interface(AudioInterface ai) {
        this.mmio.connect_audio_interface(ai);
    }

    public void connect_command_processor(CommandProcessor cp) {
        this.mmio.connect_command_processor(cp);
    }

    public void connect_dsp(DSP dsp) {
        this.mmio.connect_dsp(dsp);
    }

    public void connect_external_interface(ExternalInterface ei) {
        this.mmio.connect_external_interface(ei);
    }

    public void connect_video_interface(VideoInterface vi) {
        this.mmio.connect_video_interface(vi);
    }

    public void connect_serial_interface(SerialInterface si) {
        this.mmio.connect_serial_interface(si);
    }

    public void connect_dvd_interface(DVDInterface di) {
        this.mmio.connect_dvd_interface(di);
    }

    public void connect_interrupt_controller(InterruptController ic) {
        this.mmio.connect_interrupt_controller(ic);
    }

    public void connect_ipc(IPC ipc) {
        this.mmio.connect_ipc(ipc);
    }

    public void connect_broadway(Broadway cpu) {
        this.cpu = cpu;
    }

    public void connect_hollywood(Hollywood hollywood) {
        this.mmio.connect_hollywood(hollywood);
    }

    public void connect_pixel_engine(PixelEngine pe) {
        this.mmio.connect_pixel_engine(pe);
    }

    int mi_interrupt_mask = 0;

    public u8 read_MI_INTERRUPT_MASK(int target_byte) {
        return mi_interrupt_mask.get_byte(target_byte);
    }

    public void write_MI_INTERRUPT_MASK(int target_byte, u8 value) {
        mi_interrupt_mask = mi_interrupt_mask.set_byte(target_byte, value);
    }

    u16 mi_prot_type = 0;

    public u8 read_MI_PROT_TYPE(int target_byte) {
        return mi_prot_type.get_byte(target_byte);
    }

    public void write_MI_PROT_TYPE(int target_byte, u8 value) {
        mi_prot_type = cast(u16) mi_prot_type.set_byte(target_byte, value);
    }

    public u8 read_UNKNOWN_CC004020(int target_byte) {
        return 0;
    }

    public void write_UNKNOWN_CC004020(int target_byte, u8 value) {

    }

    u32 ahbprot_disabled = 0xFFFFFFFF;

    public u8 read_AHBPROT_DISABLED(int target_byte) {
        return ahbprot_disabled.get_byte(target_byte);
    }

    public void write_AHBPROT_DISABLED(int target_byte, u8 value) {
        ahbprot_disabled = cast(u32) ahbprot_disabled.set_byte(target_byte, value);
    }

    public void read_bulk(u8* dst, u32 address, u32 size) {
        for (int i = 0; i < size; i++) {
            dst[i] = this.physical_read_u8(address + i);
        }
    }

    public void write_bulk(u32 address, u8* data, u32 size) {
        for (int i = 0; i < size; i++) {
            this.physical_write_u8(address + i, data[i]);
        }
    }

    // u32[] logged_writes = [0x8004d040, 0x8004d044, 0x8004d048, 0x8004d04c, 0x8004d050, 0x8004d054, 0x8004d058, 0x8004d05c];
    u32[] logged_writes = [];
    void log_memory_write(u32 address) {
        logged_writes ~= address;
    }

    public u8* translate_address(u32 address) {
        MemoryAccess access = resolve_physical_address(address);
        
        final switch (access.region) {
            case MemoryRegion.MEM1:
                return &mem1[access.offset];
            case MemoryRegion.MEM2:
                return &mem2[access.offset];
            case MemoryRegion.HLE_TRAMPOLINE:
                return &hle_trampoline[access.offset];
            case MemoryRegion.LOCKED_L2_CACHE:
                return &locked_l2_cache[access.offset];
            case MemoryRegion.HOLLYWOOD_MMIO:
            case MemoryRegion.BROADWAY_MMIO:
            case MemoryRegion.EXI_BOOT_CODE:
            case MemoryRegion.EFB:
                error_memory("Cannot translate MMIO/special address %08x to host pointer", address);
                return null;
        }
    }
}
