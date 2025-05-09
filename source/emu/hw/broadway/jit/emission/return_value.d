module emu.hw.broadway.jit.emission.return_value;

enum BlockReturnValue {
    GuestBlockEnd = 0,
    ICacheInvalidation = 1,
    CpuHalted = 2,
    BranchTaken = 3,
    DecrementerChanged = 4,
    IdleLoopDetected = 5,
}