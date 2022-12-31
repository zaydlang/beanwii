module util.number;

import util.bitop;

alias u64 = ulong;
alias u32 = uint;
alias u16 = ushort;
alias u8  = ubyte;

alias s64 = long;
alias s32 = int;
alias s16 = short;
alias s8  = byte;

public bool is_number(T)() {
    return 
        is(T == u64) ||
        is(T == u32) ||
        is(T == u16) ||
        is(T == u8)  ||
        is(T == s64) ||
        is(T == s32) ||
        is(T == s16) ||
        is(T == s8);
}

public bool is_unsigned_number(T)() {
    return 
        is(T == u64) ||
        is(T == u32) ||
        is(T == u16) ||
        is(T == u8);
}

public bool is_signed_number(T)() {
    return 
        is(T == s64) ||
        is(T == s32) ||
        is(T == s16) ||
        is(T == s8);
}
