module emu.hw.broadway.jit.ir.types;

import std.conv;
import std.uni;

enum IRBinaryDataOp {
    AND,
    LSL,
    LSR,
    ASR,
    ORR,
    ADD,
    SUB,
    MUL,
    MULHI,
    MULHS,
    DIV,
    UDIV,
    XOR,
    ROL,
    GTS,
    LTS,
    GTU,
    LTU,
    EQ,
    NE
}

enum IRUnaryDataOp {
    NOT,
    NEG,
    MOV,
    ABS,
    CTZ,
    CLZ,
    POPCNT,
    FLT_CAST,
    FLT_INTERP,
    INT_CAST
}

string to_string(IRBinaryDataOp op) {
    return std.conv.to!string(op).toLower();
}

string to_string(IRUnaryDataOp op) {
    return std.conv.to!string(op).toLower();
}

enum IRCond {
    EQ = 0,
    NE = 1,
    CS = 2,
    CC = 3,
    MI = 4,
    PL = 5,
    VS = 6,
    VC = 7,
    HI = 8,
    LS = 9,
    GE = 10,
    LT = 11,
    GT = 12,
    LE = 13,
    AL = 14,

    INVALID = 15
}

enum IRFlag {
    N = 31,
    Z = 30,
    C = 29,
    V = 28,
    Q = 27,
    T = 5,

    NZCV = N | Z | C | V,
    NZC  = N | Z | C,
    NZ   = N | Z,
}