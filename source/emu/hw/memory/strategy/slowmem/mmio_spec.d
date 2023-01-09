module emu.hw.memory.strategy.slowmem.mmio_spec;

import emu.hw.cp.cp;
import emu.hw.memory.strategy.slowmem.mmio_gen;
import util.number;

final class Mmio {
    private MmioGen!(mmio_spec, Mmio) gen;

    public CommandProcessor command_processor;

    static const mmio_spec = [
        MmioRegister("command_processor", "CP_FIFO_STATUS", 0xCC00_0000, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_CONTROL",     0xCC00_0002, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_CLEAR",       0xCC00_0004, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_TOKEN",       0xCC00_000E, 2, READ_WRITE),
        MmioRegister("command_processor", "CP_FIFO_START",  0xCC00_0020, 4, READ_WRITE),
        MmioRegister("command_processor", "CP_FIFO_END",    0xCC00_0024, 4, READ_WRITE),
        MmioRegister("command_processor", "CP_FIFO_WP",     0xCC00_0034, 4, READ_WRITE),
    ];

    this(CommandProcessor command_processor) {
        this.gen = new MmioGen!(mmio_spec, Mmio)(this);

        this.command_processor = command_processor;
    }

    public T read(T)(u32 address) {
        return this.gen.read!(T)(address);
    }

    public void write(T)(u32 address, T value) {
        this.gen.write!(T)(address, value);
    }
}