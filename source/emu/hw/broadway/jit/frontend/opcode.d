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
    LHZ    = 0x28,
    LWZ    = 0x20,
    LWZU   = 0x21,
    LBZU   = 0x23,
    ORI    = 0x18,
    ORIS   = 0x19,
    RLWINM = 0x15,
    SC     = 0x11,
    STB    = 0x26,
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
    CRXOR  = 0x0C1,
    ISYNC  = 0x096,
}

enum PrimaryOp1FSecondaryOpcode {
    ADD    = 0x10A,
    CMP    = 0x000,
    CMPL   = 0x020,
    CNTLZW = 0x01A,
    DCBF   = 0x056,
    DCBI   = 0x1D6,
    DCBST  = 0x036,
    HLE    = 0x357,
    ICBI   = 0x3D6,
    LWZX   = 0x017,
    MFMSR  = 0x053,
    MFSPR  = 0x153,
    MTMSR  = 0x092,
    MTSPR  = 0x1D3,
    NOR    = 0x07C,
    OR     = 0x1BC,
    SLW    = 0x018,
    SRAW   = 0x318,
    SRW    = 0x218,
    SUBF   = 0x028,
    SYNC   = 0x256,
    XOR    = 0x13C
}
