module emu.hw.memory.strategy.hardware_accelerated_mem.hardware_accelerated_mem;

import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.cp.cp;
import emu.hw.dsp.dsp;
import emu.hw.broadway.cpu;
import emu.hw.disk.dol;
import emu.hw.hollywood.hollywood;
import emu.hw.memory.spec;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.memory.strategy.hardware_accelerated_mem.jit_memory_access;
import emu.hw.memory.strategy.hardware_accelerated_mem.mmio_spec;
import emu.hw.memory.strategy.hardware_accelerated_mem.virtualmemory;
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

final class HardwareAcceleratedMem {
    enum HLE_TRAMPOLINE_SIZE = HLE_MAX_FUNCS * 4;

    public u8[] mem1;
    public u8[] mem2;
    public u8[] hle_trampoline;
    public u8[] locked_l2_cache;

    private VirtualMemoryManager virtual_memory_manager;
    private VirtualMemorySpace* physical_memory_space;
    private VirtualMemorySpace* virtual_memory_space;
    private VirtualMemoryRegion* mem1_region;
    private VirtualMemoryRegion* mem2_region;
    private VirtualMemoryRegion* hle_trampoline_region;
    private VirtualMemoryRegion* locked_l2_cache_region;

    public Mmio mmio;
    public Broadway cpu;
    
    this() {
        this.mem1 = new u8[MEM1_SIZE];
        this.mem2 = new u8[MEM2_SIZE];
        this.hle_trampoline = new u8[HLE_TRAMPOLINE_SIZE];
        this.locked_l2_cache = new u8[0x40000];
        this.mmio = new Mmio();

        this.virtual_memory_manager = new VirtualMemoryManager();
        this.physical_memory_space = virtual_memory_manager.create_memory_space("physical_memory", 0x100000000UL);
        this.virtual_memory_space = virtual_memory_manager.create_memory_space("virtual_memory", 0x100000000UL);

        this.mem1_region = virtual_memory_manager.create_memory_region("mem1", MEM1_SIZE);
        this.mem2_region = virtual_memory_manager.create_memory_region("mem2", MEM2_SIZE);
        this.hle_trampoline_region = virtual_memory_manager.create_memory_region("hle_trampoline", HLE_TRAMPOLINE_SIZE);
        this.locked_l2_cache_region = virtual_memory_manager.create_memory_region("locked_l2_cache", 0x40000);

        virtual_memory_manager.map(physical_memory_space, mem1_region, 0x00000000);
        virtual_memory_manager.map(physical_memory_space, mem2_region, 0x10000000);
        virtual_memory_manager.map(physical_memory_space, hle_trampoline_region, 0x20000000);
        virtual_memory_manager.map(physical_memory_space, locked_l2_cache_region, 0xE0000000);

        virtual_memory_manager.map(virtual_memory_space, mem1_region, 0x80000000);
        virtual_memory_manager.map(virtual_memory_space, mem2_region, 0x90000000);
        virtual_memory_manager.map(virtual_memory_space, hle_trampoline_region, 0x20000000);
        virtual_memory_manager.map(virtual_memory_space, mem1_region, 0xC0000000);
        virtual_memory_manager.map(virtual_memory_space, mem2_region, 0xD0000000);
        virtual_memory_manager.map(virtual_memory_space, locked_l2_cache_region, 0xE0000000);

        this.mmio.connect_memory(this);
        
        set_physical_memory_base(get_physical_memory_base());
        set_virtual_memory_base(get_virtual_memory_base());
    }

    private bool is_mmio(u32 address) {
        return (address & 0x0E000000) == 0x0C000000;
    }

    public void* get_physical_memory_base() {
        return virtual_memory_manager.get_host_pointer(physical_memory_space, 0);
    }

    public void* get_virtual_memory_base() {
        return virtual_memory_manager.get_host_pointer(virtual_memory_space, 0);
    }

    private T cpu_read(T)(u32 address) {
        bool real_mode = this.cpu.state.msr.bits(4, 5) != 0b11;
        
        if (is_mmio(address)) {
            return this.mmio.read!T(address);
        } else if (0xC8000000 <= address && address <= 0xC8FFFFFF) {
            // efb i dont care
            return 0;
        }
        
        if (!real_mode) {
            return virtual_memory_manager.read_be!T(virtual_memory_space, address);
        } else {
            return virtual_memory_manager.read_be!T(physical_memory_space, address);
        }
    }

    private T physical_read(T)(u32 address) {
        if (is_mmio(address)) {
            return this.mmio.read!T(address);
        }

        return virtual_memory_manager.read_be!T(physical_memory_space, address);
    }

    public u32 cpu_read_physical_u8(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical read called with MMU enabled");
        return physical_read!u8(address);
    }

    public u32 cpu_read_physical_u16(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical read called with MMU enabled");
        return physical_read!u16(address);
    }

    public u32 cpu_read_physical_u32(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical read called with MMU enabled");
        return physical_read!u32(address);
    }

    public u64 cpu_read_physical_u64(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical read called with MMU enabled");
        return physical_read!u64(address);
    }

    public void cpu_write_physical_u8(u32 address, u32 value) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical write called with MMU enabled");
        physical_write!u8(address, cast(u8) value);
    }

    public void cpu_write_physical_u16(u32 address, u32 value) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical write called with MMU enabled");
        physical_write!u16(address, cast(u16) value);
    }

    public void cpu_write_physical_u32(u32 address, u32 value) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical write called with MMU enabled");
        physical_write!u32(address, value);
    }

    public void cpu_write_physical_u64(u32 address, u64 value) {
        assert_memory((cpu.state.msr.bits(4, 5) != 0b11), "Physical write called with MMU enabled");
        physical_write!u64(address, cast(u64) value);
    }

    private T virtual_read(T)(u32 address) {
        if (is_mmio(address)) {
            return this.mmio.read!T(address);
        } else if (0xC8000000 <= address && address <= 0xC8FFFFFF) {
            // efb i dont care
            return 0;
        }
        
        return virtual_memory_manager.read_be!T(virtual_memory_space, address);
    }

    private void virtual_write(T)(u32 address, T value) {
        if (is_mmio(address)) {
            this.mmio.write!T(address, value);
            return;
        } else if (0xC8000000 <= address && address <= 0xC8FFFFFF) {
            // efb i dont care
            return;
        }
        
        virtual_memory_manager.write_be!T(virtual_memory_space, address, value);
    }

    public u32 cpu_read_virtual_u8(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual read called with MMU disabled");
        return virtual_read!u8(address);
    }

    public u32 cpu_read_virtual_u16(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual read called with MMU disabled");
        return virtual_read!u16(address);
    }

    public u32 cpu_read_virtual_u32(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual read called with MMU disabled");
        return virtual_read!u32(address);
    }

    public u64 cpu_read_virtual_u64(u32 address) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual read called with MMU disabled");
        return virtual_read!u64(address);
    }

    public void cpu_write_virtual_u8(u32 address, u32 value) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual write called with MMU disabled");
        virtual_write!u8(address, cast(u8) value);
    }

    public void cpu_write_virtual_u16(u32 address, u32 value) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual write called with MMU disabled");
        virtual_write!u16(address, cast(u16) value);
    }

    public void cpu_write_virtual_u32(u32 address, u32 value) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual write called with MMU disabled");
        virtual_write!u32(address, value);
    }

    public void cpu_write_virtual_u64(u32 address, u64 value) {
        assert_memory((cpu.state.msr.bits(4, 5) == 0b11), "Virtual write called with MMU disabled");
        virtual_write!u64(address, cast(u64) value);
    }

    private void cpu_write(T)(u32 address, T value) {
        bool real_mode = this.cpu.state.msr.bits(4, 5) != 0b11;
        
        if (is_mmio(address)) {
            this.mmio.write!T(address, value);
            return;
        } else if (0xC8000000 <= address && address <= 0xC8FFFFFF) {
            // efb i dont care
            return;
        }
        
        if (!real_mode) {
            virtual_memory_manager.write_be!T(virtual_memory_space, address, value);
        } else {
            virtual_memory_manager.write_be!T(physical_memory_space, address, value);
        }
    }

    private void physical_write(T)(u32 address, T value) {
        if (is_mmio(address)) {
            this.mmio.write!T(address, value);
            return;
        }

        virtual_memory_manager.write_be!T(physical_memory_space, address, value);
    }

    pragma(inline, true) public u64 cpu_read_u64(u32 address) { return cpu_read!u64(address); }
    pragma(inline, true) public u32 cpu_read_u32(u32 address) { return cpu_read!u32(address); }
    pragma(inline, true) public u16 cpu_read_u16(u32 address) { return cpu_read!u16(address); }
    pragma(inline, true) public u8  cpu_read_u8 (u32 address) { return cpu_read!u8 (address); }

    pragma(inline, true) public void cpu_write_u64(u32 address, u64 value) { cpu_write!u64(address, value); }
    pragma(inline, true) public void cpu_write_u32(u32 address, u32 value) { cpu_write!u32(address, value); }
    pragma(inline, true) public void cpu_write_u16(u32 address, u16 value) { cpu_write!u16(address, value); }
    pragma(inline, true) public void cpu_write_u8 (u32 address, u8  value) { cpu_write!u8 (address, value); }

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

    u32[] logged_writes = [];
    void log_memory_write(u32 address) {
        logged_writes ~= address;
    }

    public u8* translate_address(u32 address) {
        if (is_mmio(address)) {
            error_memory("Cannot translate MMIO address %08x to host pointer", address);
        }
        
        return cast(u8*) virtual_memory_manager.to_host_address(physical_memory_space, address);
    }
}