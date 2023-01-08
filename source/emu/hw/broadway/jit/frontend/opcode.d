module emu.hw.broadway.jit.frontend.opcode;

enum PrimaryOpcode {
    ADDI   = 0x0E,
    ADDIC  = 0x0C,
    ADDIC_ = 0x0D, // since I can't do ADDIC., I'll use ADDIC_ instead
    ADDIS  = 0x0F,
    BC     = 0x10,
    B      = 0x12,
    OP_13  = 0x13,
    CMPLI  = 0x0A,
    RLWINM = 0x15,
    OP_1F  = 0x1F,
    LWZ    = 0x20,
    LBZU   = 0x23,
    STW    = 0x24,
    STWU   = 0x25,
    STBU   = 0x27
}

enum PrimaryOp13SecondaryOpcode {
    BCLR   = 0x010,
    CRXOR  = 0x0C1
}

enum PrimaryOp1FSecondaryOpcode {
    ADD    = 0x10A,
    MFSPR  = 0x153,
    MTSPR  = 0x1D3,
    OR     = 0x1BC,
    SUBF   = 0x028,
}
