module emu.hw.memory.strategy.memstrategy;

import config;

static if (config_chosen_mem_strategy == MemStrategy.SoftwareMem) {
    public import emu.hw.memory.strategy.software_mem.software_mem;
    public import emu.hw.memory.strategy.software_mem.jit_memory_access;
    alias Mem = SoftwareMem;
} else static if (config_chosen_mem_strategy == MemStrategy.HardwareAcceleratedMem) {
    public import emu.hw.memory.strategy.hardware_accelerated_mem.hardware_accelerated_mem;
    public import emu.hw.memory.strategy.hardware_accelerated_mem.jit_memory_access;
    alias Mem = HardwareAcceleratedMem;
}