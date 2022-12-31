module util.endian;

import util.bitop;
import util.number;

private enum Endianness {
    BIG,
    LITTLE
}

struct EndianType(BASETYPE, Endianness ENDIANNESS) {
    private u8[BASETYPE.sizeof] data;

    this(BASETYPE value) {
        version (BigEndian) {
            if (ENDIANNESS == Endianness.LITTLE) {
                value = bswap(value);
            }
        }

        version (LittleEndian) {
            if (ENDIANNESS == Endianness.BIG) {
                value = bswap(value);
            }
        }
        
        data[] = *cast(u8[BASETYPE.sizeof]*) &value;
    }
    
    public BASETYPE opCast(T : BASETYPE)() {
        BASETYPE converted = *(cast(BASETYPE*) data);

        version (BigEndian) {
            if (ENDIANNESS == Endianness.LITTLE) {
                return bswap(converted);
            } else {
                return converted;
            }
        }

        version (LittleEndian) {
            if (ENDIANNESS == Endianness.BIG) {
                return bswap(converted);
            } else {
                return converted;
            }
        }
    }
}

public u64_be opCast(T : u64_be)(u64 value) { return u64_be(value); }
public u32_be opCast(T : u32_be)(u32 value) { return u32_be(value); }
public u16_be opCast(T : u16_be)(u16 value) { return u16_be(value); }

public s64_be opCast(T : s64_be)(s64 value) { return s64_be(value); }
public s32_be opCast(T : s32_be)(s32 value) { return s32_be(value); }
public s16_be opCast(T : s16_be)(s16 value) { return s16_be(value); }

public u64_le opCast(T : u64_le)(u64 value) { return u64_le(value); }
public u32_le opCast(T : u32_le)(u32 value) { return u32_le(value); }
public u16_le opCast(T : u16_le)(u16 value) { return u16_le(value); }

public s64_le opCast(T : s64_le)(s64 value) { return s64_le(value); }
public s32_le opCast(T : s32_le)(s32 value) { return s32_le(value); }
public s16_le opCast(T : s16_le)(s16 value) { return s16_le(value); }

alias u64_be = EndianType!(u64, Endianness.BIG);
alias u32_be = EndianType!(u32, Endianness.BIG);
alias u16_be = EndianType!(u16, Endianness.BIG);

alias s64_be = EndianType!(s64, Endianness.BIG);
alias s32_be = EndianType!(s32, Endianness.BIG);
alias s16_be = EndianType!(s16, Endianness.BIG);

alias u64_le = EndianType!(u64, Endianness.LITTLE);
alias u32_le = EndianType!(u32, Endianness.LITTLE);
alias u16_le = EndianType!(u16, Endianness.LITTLE);

alias s64_le = EndianType!(s64, Endianness.LITTLE);
alias s32_le = EndianType!(s32, Endianness.LITTLE);
alias s16_le = EndianType!(s16, Endianness.LITTLE);
