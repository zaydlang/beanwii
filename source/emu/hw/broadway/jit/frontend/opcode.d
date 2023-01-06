module emu.hw.broadway.jit.frontend.opcode;

enum PrimaryOpcode {
    ADDI   = 0xE,
    ADDIS  = 0xF,
    B      = 0x12,
    BCLR   = 0x13,
    RLWINM = 0x15,
    OP_31  = 0x1F,
    LWZ    = 0x20,
    STW    = 0x24,
    STWU   = 0x25
}

enum PrimaryOp31SecondaryOpcode {
    MFSPR  = 0x153,
    MTSPR  = 0x1D3,
}
