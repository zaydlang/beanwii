module emu.hw.broadway.jit.emission.return_value;

enum BlockReturnValue {
    Invalid = 0,
    ICacheInvalidation = 1,
    CpuHalted = 2,
    BranchTaken = 3,
    GuestBlockEnd = 4,
    DecrementerChanged = 5,
}