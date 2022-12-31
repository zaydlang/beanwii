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
    assert (is_number!T);
    return (value & (value - 1)) == 0;
}

public size_t bfs(T)(T value) {
    assert (is_number!T);
    static import core.bitop;
    return core.bitop.bsf(value);
}
