module emu.hw.broadway.jit.emission.return_value;

enum BlockReturnValue {
    GuestBlockEnd            = 0x00,
    ICacheInvalidation       = 0x01,
    CpuHalted                = 0x02,
    PatchableBranchTaken     = 0x03,
    UnpatchableBranchTaken   = 0x04,
    DecrementerChanged       = 0x05,
    IdleLoopDetected         = 0x06,
    FloatingPointUnavailable = 0x07,

    // can be or'd with other values
    BreakpointHit            = 0x80
}

int value(BlockReturnValue value) {
    return cast(int) value & ~BlockReturnValue.BreakpointHit;
}

int breakpoint_hit(BlockReturnValue value) {
    return (value & BlockReturnValue.BreakpointHit) != 0;
}