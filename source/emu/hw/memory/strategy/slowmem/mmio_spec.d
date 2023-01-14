module emu.hw.memory.strategy.slowmem.mmio_spec;

import emu.hw.cp.cp;
import emu.hw.memory.strategy.slowmem.mmio_gen;
import emu.hw.si.si;
import emu.hw.vi.vi;
import util.number;

final class Mmio {
    private MmioGen!(mmio_spec, Mmio) gen;

    public CommandProcessor command_processor;
    public VideoInterface   video_interface;
    public SerialInterface  serial_interface;

    static const mmio_spec = [
        MmioRegister("command_processor", "CP_FIFO_STATUS", 0xCC00_0000, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_CONTROL",     0xCC00_0002, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_CLEAR",       0xCC00_0004, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_TOKEN",       0xCC00_000E, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_FIFO_START",  0xCC00_0020, 4, READ_WRITE),
        MmioRegister("command_processor", "CP_FIFO_END",    0xCC00_0024, 4, READ_WRITE),
        MmioRegister("command_processor", "CP_FIFO_WP",     0xCC00_0034, 4, READ_WRITE),
        MmioRegister("video_interface",   "VTR",            0xCC00_2000, 2, READ_WRITE),
        MmioRegister("video_interface",   "DCR",            0xCC00_2002, 2, READ_WRITE),
        MmioRegister("video_interface",   "HTR0",           0xCC00_2004, 4, READ_WRITE),
        MmioRegister("video_interface",   "HTR1",           0xCC00_2008, 4, READ_WRITE),
        MmioRegister("video_interface",   "VTO",            0xCC00_200C, 4, READ_WRITE),
        MmioRegister("video_interface",   "VTE",            0xCC00_2010, 4, READ_WRITE),
        MmioRegister("video_interface",   "BBEI",           0xCC00_2014, 4, READ_WRITE),
        MmioRegister("video_interface",   "BBOI",           0xCC00_2018, 4, READ_WRITE),
        MmioRegister("video_interface",   "TFBL",           0xCC00_201C, 4, READ_WRITE),
        MmioRegister("video_interface",   "BFBL",           0xCC00_2024, 4, READ_WRITE),
        MmioRegister("video_interface",   "HSR",            0xCC00_204A, 2, READ_WRITE),
        MmioRegister("video_interface",   "FCTx",           0xCC00_204C, 4, READ_WRITE).repeat(7, 4),
        MmioRegister("video_interface",   "UNKNOWN",        0xCC00_2070, 2, READ_WRITE),
        MmioRegister("video_interface",   "VICLK",          0xCC00_206C, 2, READ_WRITE),
        MmioRegister("serial_interface",  "SICxOUTBUF",     0xCD00_6400, 4, READ_WRITE).repeat(4, 0xC),
        MmioRegister("serial_interface",  "SIPOLL",         0xCD00_6430, 4, READ_WRITE),
    ];

    this() {
        this.gen = new MmioGen!(mmio_spec, Mmio)(this);
    }

    public T read(T)(u32 address) {
        return this.gen.read!(T)(address);
    }

    public void write(T)(u32 address, T value) {
        this.gen.write!(T)(address, value);
    }

    public void connect_command_processor(CommandProcessor command_processor) {
        this.command_processor = command_processor;
    }

    public void connect_video_interface(VideoInterface video_interface) {
        this.video_interface = video_interface;
    }

    public void connect_serial_interface(SerialInterface serial_interface) {
        this.serial_interface = serial_interface;
    }
}