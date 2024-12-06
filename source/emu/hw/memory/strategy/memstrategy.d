module emu.hw.memory.strategy.memstrategy;

import emu.hw.broadway.interrupt;
import emu.hw.cp.cp;
import emu.hw.disk.dol;
import emu.hw.memory.strategy.slowmem.slowmem;
import emu.hw.ai.ai;
import emu.hw.dsp.dsp;
import emu.hw.exi.exi;
import emu.hw.si.si;
import emu.hw.vi.vi;
import emu.hw.ipc.ipc;
import util.number;

alias Mem = SlowMem;

interface MemStrategy {
    // interfaces cant have templated functions, so we have to do this:
    public u64 read_be_u64(u32 address);
    public u32 read_be_u32(u32 address);
    public u16 read_be_u16(u32 address);
    public u8  read_be_u8 (u32 address);

    public void write_be_u64(u32 address, u64 value);
    public void write_be_u32(u32 address, u32 value);
    public void write_be_u16(u32 address, u16 value);
    public void write_be_u8 (u32 address, u8  value);

    public u8 paddr_read_u8(u32 address);
    public u16 paddr_read_u16(u32 address);
    public u32 paddr_read_u32(u32 address);
    public u64 paddr_read_u64(u32 address);
    public void paddr_write_u8(u32 address, u8 value);
    public void paddr_write_u16(u32 address, u16 value);
    public void paddr_write_u32(u32 address, u32 value);
    public void paddr_write_u64(u32 address, u64 value);
    
    public void map_buffer(u8* buffer, size_t buffer_size, u32 address);
    public void map_dol(WiiDol* dol);

    public void connect_audio_interface(AudioInterface ai);
    public void connect_command_processor(CommandProcessor cp);
    public void connect_dsp(DSP dsp);
    public void connect_external_interface(ExternalInterface ei);
    public void connect_video_interface(VideoInterface vi);
    public void connect_serial_interface(SerialInterface si);
    public void connect_interrupt_controller(InterruptController ic);
    public void connect_ipc(IPC ipc);

    public u8   read_MI_INTERRUPT_MASK(int target_byte);
    public void write_MI_INTERRUPT_MASK(int target_byte, u8 value);

    public u8   read_UNKNOWN_CC004020(int target_byte);
    public void write_UNKNOWN_CC004020(int target_byte, u8 value);

    public u8   read_MI_PROT_TYPE(int target_byte);
    public void write_MI_PROT_TYPE(int target_byte, u8 value);
}
