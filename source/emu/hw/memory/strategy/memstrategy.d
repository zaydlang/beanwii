module emu.hw.memory.strategy.memstrategy;

enum MemStrategy {
    SoftwareMem,
    HardwareAcceleratedMem,
}

enum ChosenMemStrategy = MemStrategy.HardwareAcceleratedMem;

static if (ChosenMemStrategy == MemStrategy.SoftwareMem) {
    public import emu.hw.memory.strategy.software_mem.software_mem;
    public import emu.hw.memory.strategy.software_mem.jit_memory_access;
    alias Mem = SoftwareMem;
} else static if (ChosenMemStrategy == MemStrategy.HardwareAcceleratedMem) {
    public import emu.hw.memory.strategy.hardware_accelerated_mem.hardware_accelerated_mem;
    public import emu.hw.memory.strategy.hardware_accelerated_mem.jit_memory_access;
    alias Mem = HardwareAcceleratedMem;
}