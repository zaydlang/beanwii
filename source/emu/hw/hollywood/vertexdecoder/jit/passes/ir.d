module emu.hw.hollywood.vertexdecoder.jit.passes.ir;

import emu.hw.hollywood.hollywood_types;
import util.number;

enum OpKind : u8 {
    Sext,
    Zext,
    Mul,
    DequantizeColor,
    CvtToFloat,
    Store,
    IndexedLoad,
}

enum IndexedAttrKind : u8 {
    Coord,
    Normal,
    Color,
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
        IndexedLoad     indexed_load;
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

struct IndexedLoad {
    u8              stream_offset;
    u8              index_size;       // 1 or 2
    u8              array_number;
    IndexedAttrKind attr_kind;
    u8              component_count;
    float           scale;            // 1.0 if no scaling

    // For nine-component normals (NBT), the array element contains all 9
    // components contiguously, but the JIT splits them into three separate
    // 3-component loads (normal, binormal_t, binormal_b). This field tells
    // the emission code which component to start reading from within the
    // array element. For example, binormal_t starts at component 3 and
    // binormal_b starts at component 6.
    u8              first_component_index;

    u8              ymm_index;
    u8              ymm_byte_offset;

    union {
        CoordFormat  coord_format;
        NormalFormat normal_format;
        ColorFormat  color_format;
    }
}

// Describes a contiguous 32-byte window in the source stream that should
// be loaded into a YMM register before executing ops that reference it.
struct YmmDescriptor {
    u32 offset;
    u32 index;
}
