module emu.hw.memory.strategy.memstrategy;

enum MemStrategy {
    SlowMem,
    FastMem,
}

enum ChosenMemStrategy = MemStrategy.FastMem;

static if (ChosenMemStrategy == MemStrategy.SlowMem) {
    public import emu.hw.memory.strategy.slowmem.slowmem;
    public import emu.hw.memory.strategy.slowmem.jit_memory_access;
    alias Mem = SlowMem;
} else static if (ChosenMemStrategy == MemStrategy.FastMem) {
    public import emu.hw.memory.strategy.fastmem.fastmem;
    public import emu.hw.memory.strategy.fastmem.jit_memory_access;
    alias Mem = FastMem;
}