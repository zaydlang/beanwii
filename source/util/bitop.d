module util.bitop;

import util.number;

public u8 bswap(u8 value) {
    return value;
}

public u16 bswap(u16 value) {
    return (value >> 8) | ((value & 0xFF) << 8);
}

public u32 bswap(u32 value) {
    static import core.bitop;
    return core.bitop.bswap(value);
}

public u64 bswap(u64 value) {
    static import core.bitop;
    return core.bitop.bswap(value);
}

public bool is_pow_2(T)(T value) {
    assert(is_number!T);
    return (value & (value - 1)) == 0;
}

public size_t bfs(T)(T value) {
    assert(is_number!T);
    static import core.bitop;
    return core.bitop.bsf(value);
}

public T bits(T)(T value, size_t start, size_t end) {
    assert(end > start);
    assert(is_number!T);
    assert(end <= T.sizeof * 8);
    assert(start < T.sizeof * 8);

    auto mask = create_mask(start, end);
    return (value & mask) >> start;
}

public bool bit(T)(T value, size_t index) { 
    assert(index < T.sizeof * 8);
    assert(is_number!T);

    return (value >> index) & 1;
}

public s64 sext_64(T)(T value, u32 size) {
    assert(is_number!T);
    
    auto negative = value.bit(size - 1);
    s32 result = value;

    if (negative) result |= (((1UL << (64 - size)) - 1) << size);
    return result;
}

public s32 sext_32(T)(T value, u32 size) {
    assert(is_number!T);
    
    auto negative = value.bit(size - 1);
    s32 result = value;

    if (negative) result |= (((1 << (32 - size)) - 1) << size);
    return result;
}

public s16 sext_16(T)(T value, u32 size) {
    assert(is_number!T);
    
    auto negative = value.bit(size - 1);
    s16 result = value;

    if (negative) result |= (((1 << (16 - size)) - 1) << size);
    return result;
}

public u8 get_byte(T)(T value, int index) {
    assert(is_number!T);
    assert(index < T.sizeof);

    return (value >> (index * 8)) & 0xFF;
}

public u32 set_byte(T)(T value, int index, u8 b) {
    assert(is_number!T);
    assert(index < T.sizeof);

    return (value & ~(0xFF << (index * 8))) | (b << (index * 8));
}

public auto create_mask(size_t start, size_t end) {
    if (end - start >= 31) return 0xFFFFFFFF;

    return ((1 << (end - start + 1)) - 1) << start;
}