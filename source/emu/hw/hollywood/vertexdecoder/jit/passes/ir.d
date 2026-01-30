module emu.hw.hollywood.vertexdecoder.jit.passes.ir;

import emu.hw.hollywood.hollywood_types;
import util.number;

enum OpKind : u8 {
    Sext,
    Zext,
    Mul,
    DequantizeColor,
    CvtToFloat,
    Store
}

enum Size : u8 {
    Size8  = 1,
    Size16 = 2,
    Size32 = 4,
}

struct Op {
    OpKind kind;

    // Bitmask of memory that this operation will affect
    u64 source_mask;

    // Which YMM chunk (computed during allocation) this op reads from
    u8  ymm_index;

    union {
        Sext            sext;
        Zext            zext;
        Mul             mul;
        DequantizeColor dequantize_color;
        // no parameters for CvtToFloat
        Store           store;
    }    
}

// Sext always sign-extends to 32 bits
struct Sext {
    Size from;
}

// Zext always zero-extends to 32 bits
struct Zext {
    Size from;
}

struct Mul {
    float factor;
}

struct DequantizeColor {
    ColorFormat format;
}

struct Store {
    u32 dest_offset;
}

// Describes a contiguous 32-byte window in the source stream that should
// be loaded into a YMM register before executing ops that reference it.
struct YmmDescriptor {
    u32 offset;
    u32 index;
}
