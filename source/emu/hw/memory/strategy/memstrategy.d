module emu.hw.memory.strategy.memstrategy;

import emu.hw.cp.cp;
import emu.hw.disk.dol;
import emu.hw.memory.strategy.slowmem.slowmem;
import emu.hw.si.si;
import emu.hw.vi.vi;
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
    
    public void map_buffer(u8* buffer, size_t buffer_size, u32 address);
    public void map_dol(WiiDol* dol);

    public void connect_command_processor(CommandProcessor cp);
    public void connect_video_interface(VideoInterface vi);
    public void connect_serial_interface(SerialInterface si);
}
