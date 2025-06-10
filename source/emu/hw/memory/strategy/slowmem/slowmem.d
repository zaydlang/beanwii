module emu.hw.memory.strategy.slowmem.slowmem;

import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.cp.cp;
import emu.hw.dsp.dsp;
import emu.hw.broadway.cpu;
import emu.hw.disk.dol;
import emu.hw.hollywood.hollywood;
import emu.hw.memory.spec;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.memory.strategy.slowmem.mmio_spec;
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

// NOTE: this memstrategy is VERY slow! It's very simplistic, and only
// here for basic testing purposes.
final class SlowMem : MemStrategy {
    enum HLE_TRAMPOLINE_SIZE = HLE_MAX_FUNCS * 4;

    enum MemoryRegion {
        MEM1,
        MEM2,
        HLE_TRAMPOLINE,
        HOLLYWOOD_MMIO,
        BROADWAY_MMIO,
        EXI_BOOT_CODE
    }

    struct MemoryAccess {
        MemoryRegion region;
        u32 offset;
    }

    // TODO: temporary public
    public u8[] mem1;
    public u8[] mem2;
    public u8[] hle_trampoline;

    public Mmio mmio;
    public Broadway cpu;
    
    this() {
        this.mem1 = new u8[MEM1_SIZE];
        this.mem2 = new u8[MEM2_SIZE];
        this.hle_trampoline = new u8[HLE_TRAMPOLINE_SIZE];
        this.mmio = new Mmio();
        // log_wii("mem1 base: %x", this.mem1.ptr);

        this.mmio.connect_memory(this);
    }

    private MemoryAccess get_memory_access_from_paddr(u32 address) {
        if        (0x00000000 <= address && address <= 0x017FFFFF) {
            return MemoryAccess(MemoryRegion.MEM1, address);
        } else if (0x10000000 <= address && address <= 0x13FFFFFF) {
            return MemoryAccess(MemoryRegion.MEM2, address - 0x10000000);
        } else if (0x0D000000 <= address && address <= 0x0D008000) {
            return MemoryAccess(MemoryRegion.HOLLYWOOD_MMIO, address & 0x7FFF);
        } else if (0x0C000000 <= address && address <= 0x0C008003) {
            return MemoryAccess(MemoryRegion.BROADWAY_MMIO, address & 0x7FFF);
        } else if (0xFFF00100 <= address && address <= 0xFFF0013F) {
            return MemoryAccess(MemoryRegion.EXI_BOOT_CODE, address & 0x3F);
        } else {
            error_slowmem("Invalid address 0x%08x", address);
            assert(0);
        }
    }

    private MemoryAccess translate_vaddr_to_paddr(u32 address) {
        // inaccurate but lets gooooo

        bool real_mode = this.cpu.state.msr.bits(4, 5) != 0b11;

        if (!real_mode) {
            // See: wii.setup_global_memory_value(u8[] wii_disk_data);
            // assert(address != 0x8000_3198);

            if        (0x80000000 <= address && address <= 0x817FFFFF) {
                return MemoryAccess(MemoryRegion.MEM1, address - 0x80000000);
            } else if (0x90000000 <= address && address <= 0x93FFFFFF) {
                return MemoryAccess(MemoryRegion.MEM2, address - 0x90000000);
            } else if (0xC0000000 <= address && address <= 0xC17FFFFF) {
                return MemoryAccess(MemoryRegion.MEM1, address - 0xC0000000);
            } else if (0xD0000000 <= address && address <= 0xD3FFFFFF) {
                return MemoryAccess(MemoryRegion.MEM2, address - 0xD0000000);
            } else if (0xCC000000 <= address && address <= 0xCDFFFFFF) {
                return MemoryAccess(MemoryRegion.HOLLYWOOD_MMIO, address & 0x7FFF);
            } else if (0x20000000 <= address && address <= 0x2FFFFFFF) {
                return MemoryAccess(MemoryRegion.HLE_TRAMPOLINE, address - 0x20000000);
            } else {
                error_slowmem("Invalid address 0x%08x", address);
                assert(0);
            }


            // auto region = address >> 28;

            // switch (region) {
            //     case 0x8: 
            //         if (address < 0x81800000) {
            //             return MemoryAccess(MemoryRegion.MEM1, address);
            //         } else {
            //             break;
            //         } 
            //     case 0x9: 
            //         if (address < 0x93FFFFFF) {
            //             return MemoryAccess(MemoryRegion.MEM2, address);
            //         } else {
            //             break;
            //         } 
            //     case 0xC: 
            //         if (address <= 0xC17FFFFF) {
            //             return MemoryAccess(MemoryRegion.MEM1,             address & 0x17FFFFF);
            //         } else {
            //             return MemoryAccess(MemoryRegion.HOLLYWOOD_MMIO,   address & 0x3FFFFF);
            //         }

            //     case 0xD: return MemoryAccess(MemoryRegion.MEM2,           address & 0x3FFFFFF);
            //     case 0x2: return MemoryAccess(MemoryRegion.HLE_TRAMPOLINE, address & 0x3FFFFF);
            //     default:
            //         error_slowmem("Invalid region 0x%08x (0x%08x)", region, address);
            //         assert(0);
            // }

        } else {
            return get_memory_access_from_paddr(address);
        }
    }


    private T read_be(T, bool translate)(u32 address) {
        // log_broadway("statepc: %x", cpu.state.pc);
        static if (translate) {
            auto memory_access = this.translate_vaddr_to_paddr(address);
        } else {
            auto memory_access = get_memory_access_from_paddr(address);
        }

        auto region = memory_access.region;

        T result;

        if (address == 0x806577e0) {
            log_disk("dumbass %x %x", cpu.state.pc, cpu.state.lr);
        }

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
                result = this.mmio.read!T(address);
                break;

            case MemoryRegion.BROADWAY_MMIO:
                result = this.mmio.read!T(address);
                break;

            case MemoryRegion.EXI_BOOT_CODE:
                error_slowmem("Read from EXI boot code at 0x%08x", address);
                break;
        }

        if (address == 0x8050b8a8 || address == 0x0050b8a8) {
            log_slowmem("disker in use read: %x %x %x", address, result, cpu.state.pc);
        }

        // log_slowmem("Read from 0x%08x = 0x%08x", address, result);


        if (cpu.state.pc == 0x802956f8) {
            log_ipc("Read from ipc mailbox: %x %x", result, address);
        }
        return result;
    }

    private void write_be(T, bool translate)(u32 address, T value) {
        foreach (logged_write; logged_writes) {
            if (address == logged_write) {
                import std.stdio;
                writefln("  Write to 0x%08x = 0x%08x (pc: %x, lr: %x)", address, value, cpu.state.pc, cpu.state.lr);
            }
        }
        // log_broadway("statepc: %x", cpu.state.pc);
        static if (translate) {
            auto memory_access = this.translate_vaddr_to_paddr(address);
        } else {
            auto memory_access = get_memory_access_from_paddr(address);
        }

        if (address == 0x8076ae40 + 0x168) {
            log_wii("IMPORTANT Write to 0x%08x = 0x%08x", address, value);
        }

        if (address == 0x8076ae40 + 0x164) {
            log_wii("IMPORTANT Write to 0x%08x = 0x%08x", address, value);
        }

        if (address == 0x8076ae40 + 0x15c) {
            log_wii("IMPORTANT Write to 0x%08x = 0x%08x", address, value);
        }

        if (address == 0x8076ae40 + 0x170) {
            log_wii("IMPORTANT Write to 0x%08x = 0x%08x", address, value);
        }




        if (address == 0x8056dce0) {
            log_slowmem("disker inUse index: %x %x", value, cpu.state.pc);
        }

        if (address == 0x804f1ff8) {
            log_ipc("dipshit fd: %x %x", value, cpu.state.pc);
        }

        if (address == 0x056d1d0 + 0x16 || address == 0x056d1d0 + 0x14) {
            log_ipc("dipshit fd: %x %x", value, cpu.state.pc);
        }

        if (address == 0x8050b8a8 || address == 0x0050b8a8) {
            log_slowmem("disker in use: %x %x %x", address, value, cpu.state.pc);
        }

        if (address == 0x8056deb8) {
            log_broadway("DSP STATE: %x %x", value, cpu.state.pc);
        }

        if (address == 0x8056df50) {
            log_broadway("__dsp_rudetask_pend = %x %x", value, cpu.state.pc);
        }

        if (address == 2 + 0x803b4250) {
            log_broadway("bta2_hh_maint_dev_act.action1 = %x %x", value, cpu.state.pc);
        }

        if (address == 8 + 0x803b4250) {
            log_broadway("bta2_hh_maint_dev_act.action2 = %x %x", value, cpu.state.pc);
        }


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
                this.mmio.write!T(address, value);
                break;

            case MemoryRegion.BROADWAY_MMIO:
                this.mmio.write!T(address, value);
                break;

            case MemoryRegion.EXI_BOOT_CODE:
                error_slowmem("Write to EXI boot code at 0x%08x", address);
                break;
        }

        // log_slowmem("Write to 0x%08x = 0x%08x", address, value);
    }

    pragma(inline, true) override public u64 read_be_u64(u32 address) { return read_be!(u64, true)(address); }
    pragma(inline, true) override public u32 read_be_u32(u32 address) { return read_be!(u32, true)(address); }
    pragma(inline, true) override public u16 read_be_u16(u32 address) { return read_be!(u16, true)(address); }
    pragma(inline, true) override public u8  read_be_u8 (u32 address) { return read_be!(u8 , true)(address); }

    pragma(inline, true) override public void write_be_u64(u32 address, u64 value) { write_be!(u64, true)(address, value); }
    pragma(inline, true) override public void write_be_u32(u32 address, u32 value) { write_be!(u32, true)(address, value); }
    pragma(inline, true) override public void write_be_u16(u32 address, u16 value) { write_be!(u16, true)(address, value); }
    pragma(inline, true) override public void write_be_u8 (u32 address, u8  value) { write_be!(u8 , true)(address, value); }

    pragma(inline, true) override public u8 paddr_read_u8(u32 address) {
        return this.read_be!(u8, false)(address);
    }

    pragma(inline, true) override public u16 paddr_read_u16(u32 address) {
        return this.read_be!(u16, false)(address);
    }

    pragma(inline, true) override public u32 paddr_read_u32(u32 address) {
        return this.read_be!(u32, false)(address);
    }

    pragma(inline, true) override public u64 paddr_read_u64(u32 address) {
        return this.read_be!(u64, false)(address);
    }

    pragma(inline, true) override public void paddr_write_u8(u32 address, u8 value) {
        this.write_be!(u8, false)(address, value);
    }

    pragma(inline, true) override public void paddr_write_u16(u32 address, u16 value) {
        this.write_be!(u16, false)(address, value);
    }

    pragma(inline, true) override public void paddr_write_u32(u32 address, u32 value) {
        this.write_be!(u32, false)(address, value);
    }

    pragma(inline, true) override public void paddr_write_u64(u32 address, u64 value) {
        this.write_be!(u64, false)(address, value);
    }

    override public void map_buffer(u8* buffer, size_t buffer_size, u32 address) {
        for (int i = 0; i < buffer_size; i++) {
            this.write_be!(u8, true)(address + i, buffer[i]);
        }
    }

    override public void map_dol(WiiDol* dol) {
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 text_address = cast(u32) dol.header.text_address[i];
            u32 text_offset  = cast(u32) dol.header.text_offset[i];
            u32 text_size    = cast(u32) dol.header.text_size[i];

            u32 dol_data_offset = text_offset - cast(int) WiiDolHeader.sizeof;

            if (text_size == 0) continue;

            // log_disk("Mapping text section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, text_address, text_offset, text_size);
            map_buffer(&dol.data.ptr[dol_data_offset], text_size, text_address);
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 data_address = cast(u32) dol.header.data_address[i];
            u32 data_offset  = cast(u32) dol.header.data_offset[i];
            u32 data_size    = cast(u32) dol.header.data_size[i];

            u32 dol_data_offset = data_offset - cast(int) WiiDolHeader.sizeof;

            if (data_size == 0) continue;
            
            // log_disk("Mapping data section %d at 0x%08X, offset 0x%08X, size 0x%08X", i, data_address, data_offset, data_size);
            map_buffer(&dol.data.ptr[dol_data_offset], data_size, data_address);
        }

        u32 bss_address = cast(u32) dol.header.bss_address;
        u32 bss_size    = cast(u32) dol.header.bss_size;

        if (bss_size != 0) {
            // log_disk("Mapping BSS at 0x%08X, size 0x%08X", bss_address, bss_size);
            for (int i = 0; i < cast(u32) dol.header.bss_size; i++) {
                this.write_be!(u8, true)(bss_address + i, 0x00);
            }
        }

        // log_disk("Entrypoint: %x", cast(u32) dol.header.entry_point);
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

    override public void read_bulk(u8* dst, u32 address, u32 size) {
        for (int i = 0; i < size; i++) {
            dst[i] = this.paddr_read_u8(address + i);
        }
    }

    override public void write_bulk(u32 address, u8* data, u32 size) {
        for (int i = 0; i < size; i++) {
        if (address + i == 0x004f0c7c) {
            log_disk("Big baller biswadev dev roy back at it again: %x", data[i]);
        }
            this.paddr_write_u8(address + i, data[i]);
        }
    }

    u32[] logged_writes = [];
    void log_memory_write(u32 address) {
        logged_writes ~= address;
    }
}