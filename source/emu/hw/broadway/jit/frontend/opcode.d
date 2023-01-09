module emu.hw.broadway.jit.frontend.opcode;

enum PrimaryOpcode {
    ADDI   = 0x0E,
    ADDIC  = 0x0C,
    ADDIC_ = 0x0D, // since I can't do ADDIC., I'll use ADDIC_ instead
    ADDIS  = 0x0F,
    B      = 0x12,
    BC     = 0x10,
    CMPLI  = 0x0A,
    CMPI   = 0x0B,
    LWZ    = 0x20,
    LBZU   = 0x23,
    ORI    = 0x18,
    RLWINM = 0x15,
    STBU   = 0x27,
    STH    = 0x2C,
    STW    = 0x24,
    STWU   = 0x25,

    OP_13  = 0x13,
    OP_1F  = 0x1F,
}

enum PrimaryOp13SecondaryOpcode {
    BCCTR  = 0x210,
    BCLR   = 0x010,
    CRXOR  = 0x0C1
}

enum PrimaryOp1FSecondaryOpcode {
    ADD    = 0x10A,
    CMPL   = 0x020,
    DCBST  = 0x036,
    HLE    = 0x357,
    MFSPR  = 0x153,
    MTSPR  = 0x1D3,
    NOR    = 0x07C,
    OR     = 0x1BC,
    SUBF   = 0x028,
}
