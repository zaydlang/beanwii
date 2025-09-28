module emu.hw.dsp.jit.emission.flags;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.jit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import gallinule.x86;
import util.number;
import util.log;

struct FlagState {
    u8 flag_c;
    u8 flag_o;
    u8 flag_az;
    u8 flag_s;
    u8 flag_s32;
    u8 flag_tb;
    u8 flag_lz;
    u8 flag_os;

    static Address!8 flag_c_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_c.offsetof));
    }

    static Address!8 flag_o_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_o.offsetof));
    }

    static Address!8 flag_az_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_az.offsetof));
    }

    static Address!8 flag_s_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_s.offsetof));
    }

    static Address!8 flag_s32_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_s32.offsetof));
    }

    static Address!8 flag_tb_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_tb.offsetof));
    }

    static Address!8 flag_lz_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_lz.offsetof));
    }

    static Address!8 flag_os_addr(DspCode code) {
        return code.bytePtr(rdi, cast(int) (DspState.flag_state.offsetof + FlagState.flag_os.offsetof));
    }

    void set(int flags) {
        flag_c   = flags & Flag.C   ? 1 : 0;
        flag_o   = flags & Flag.O   ? 1 : 0;
        flag_az  = flags & Flag.AZ  ? 1 : 0;
        flag_s   = flags & Flag.S   ? 1 : 0;
        flag_s32 = flags & Flag.S32 ? 1 : 0;
        flag_tb  = flags & Flag.TB  ? 1 : 0;
        flag_lz  = flags & Flag.LZ  ? 1 : 0;
        flag_os  = flags & Flag.OS  ? 1 : 0;
    }

    int get() {
        int flags = 0;
        if (flag_c)   flags |= Flag.C;
        if (flag_o)   flags |= Flag.O;
        if (flag_az)  flags |= Flag.AZ;
        if (flag_s)   flags |= Flag.S;
        if (flag_s32) flags |= Flag.S32;
        if (flag_tb)  flags |= Flag.TB;
        if (flag_lz)  flags |= Flag.LZ;
        if (flag_os)  flags |= Flag.OS;
        return flags;
    }
}

enum Flag {
    C   = 1 << 0,
    O   = 1 << 1,
    AZ  = 1 << 2,
    S   = 1 << 3,
    S32 = 1 << 4,
    TB  = 1 << 5,
    LZ  = 1 << 6,
    OS  = 1 << 7,
}

enum AllFlagsButLZ = Flag.C | Flag.O | Flag.AZ | Flag.S | Flag.S32 | Flag.TB | Flag.OS;
enum AllFlagsButLZAndC = Flag.O | Flag.AZ | Flag.S | Flag.S32 | Flag.TB | Flag.OS;

void emit_set_flags_addpaxz(int flags_to_set, int flags_to_reset, DspCode code, R64 result, R64 auxiliary_carry, R64 auxiliary_overflow, R64 tmp1, R64 tmp2) {
    assert_dsp((flags_to_set & flags_to_reset) == 0, "Cannot set and reset the same flag");

    if (flags_to_reset & Flag.C) {
        code.mov(FlagState.flag_c_addr(code), 0);
    }

    if (flags_to_reset & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), 0);
    }
    
    if (flags_to_set & Flag.AZ) {
        code.sete(tmp1.cvt8());
        code.mov(FlagState.flag_az_addr(code), tmp1.cvt8());
    }

    if (flags_to_set & Flag.OS || flags_to_set & Flag.O) {
        code.seto(tmp1.cvt8());
    }
    
    if (flags_to_set & Flag.C) {
        code.setc(tmp2.cvt8());
        code.xor(tmp2, auxiliary_carry);
        code.and(tmp2, 1);
    }

    if (flags_to_set & Flag.OS || flags_to_set & Flag.O) {
        code.xor(tmp1, auxiliary_overflow);
        code.and(tmp1, 1);
    }

    if (flags_to_set & Flag.C) {
        code.mov(FlagState.flag_c_addr(code), tmp2.cvt8());
    }

    if (flags_to_set & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), tmp1.cvt8());
    }

    if (flags_to_set & Flag.OS) {
        code.or(FlagState.flag_os_addr(code), tmp1.cvt8());
    }

    emit_set_flags_without_host_state(flags_to_set, code, result, tmp1);
}

void emit_set_flags_addp(int flags_to_set, int flags_to_reset, DspCode code, R64 result, R64 auxiliary_carry, R64 auxiliary_overflow, R64 tmp1, R64 tmp2) {
    assert_dsp((flags_to_set & flags_to_reset) == 0, "Cannot set and reset the same flag");

    if (flags_to_reset & Flag.C) {
        code.mov(FlagState.flag_c_addr(code), 0);
    }

    if (flags_to_reset & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), 0);
    }
    
    if (flags_to_set & Flag.AZ) {
        code.sete(tmp1.cvt8());
        code.mov(FlagState.flag_az_addr(code), tmp1.cvt8());
    }

    if (flags_to_set & Flag.C) {
        code.setc(tmp1.cvt8());
    }
    
    if (flags_to_set & Flag.OS || flags_to_set & Flag.O) {
        code.seto(tmp2.cvt8());
        code.xor(tmp2, auxiliary_overflow);
        code.and(tmp2, 1);
    }

    if (flags_to_set & Flag.C) {
        code.or(tmp1, auxiliary_carry);
        code.mov(FlagState.flag_c_addr(code), tmp1.cvt8());
    }

    if (flags_to_set & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), tmp2.cvt8());
    }

    if (flags_to_set & Flag.OS) {
        code.or(FlagState.flag_os_addr(code), tmp2.cvt8());
    }

    emit_set_flags_without_host_state(flags_to_set, code, result, tmp1);
}

void emit_set_flags_andi(int flags_to_set, int flags_to_reset, DspCode code, R64 result, R64 ac_full, R64 tmp) {
    assert_dsp((flags_to_set & flags_to_reset) == 0, "Cannot set and reset the same flag");

    if (flags_to_reset & Flag.C) {
        code.mov(FlagState.flag_c_addr(code), 0);
    }

    if (flags_to_reset & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), 0);
    }

    if (flags_to_set & Flag.AZ) {
        code.sete(tmp.cvt8());
        code.mov(FlagState.flag_az_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.OS) {
        code.seto(tmp.cvt8());
        code.or(FlagState.flag_os_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.S) {
        code.mov(tmp, result);
        code.sar(tmp, 63);
        code.mov(FlagState.flag_s_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.S32) {
        code.mov(tmp, 1L << 55);
        code.add(tmp, ac_full);
        code.sar(tmp, 56);
        code.setne(tmp.cvt8());
        code.mov(FlagState.flag_s32_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.TB) {
        // top two bits equal
        code.mov(tmp, result); 
        code.shl(tmp, 1);
        code.xor(tmp, result);
        code.not(tmp);
        code.shr(tmp, 64 - 1);
        code.mov(FlagState.flag_tb_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.LZ) {
        // dunno yet lol
    }
}

void emit_set_flags(int flags_to_set, int flags_to_reset, DspCode code, R64 result, R64 tmp) {
    assert_dsp((flags_to_set & flags_to_reset) == 0, "Cannot set and reset the same flag");

    if (flags_to_reset & Flag.C) {
        code.mov(FlagState.flag_c_addr(code), 0);
    }

    if (flags_to_reset & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), 0);
    }

    // TODO: this is technically worng when we add flag analyssi
    if (flags_to_reset & Flag.S32) {
        code.mov(FlagState.flag_s32_addr(code), 1);
    }

    if (flags_to_set & Flag.C) {
        code.setc(tmp.cvt8());
        code.mov(FlagState.flag_c_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.O) {
        code.seto(tmp.cvt8());
        code.mov(FlagState.flag_o_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.AZ) {
        code.sete(tmp.cvt8());
        code.mov(FlagState.flag_az_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.OS) {
        code.seto(tmp.cvt8());
        code.or(FlagState.flag_os_addr(code), tmp.cvt8());
    }

    emit_set_flags_without_host_state(flags_to_set, code, result, tmp);
}

void emit_set_flags_sub(int flags_to_set, int flags_to_reset, DspCode code, R64 result, R64 src2, R64 tmp1, R64 tmp2, R64 tmp3) {
    assert_dsp((flags_to_set & flags_to_reset) == 0, "Cannot set and reset the same flag");

    if (flags_to_reset & Flag.C) {
        code.mov(FlagState.flag_c_addr(code), 0);
    }

    if (flags_to_reset & Flag.O) {
        code.mov(FlagState.flag_o_addr(code), 0);
    }

    if (flags_to_set & Flag.AZ) {
        code.sete(tmp1.cvt8());
        code.mov(FlagState.flag_az_addr(code), tmp1.cvt8());
    }

    assert_dsp(
        (flags_to_set & (Flag.OS | Flag.C | Flag.O)) == (Flag.OS | Flag.C | Flag.O),
        "OS, O, and C flags must be set"
    );

    code.setc(tmp1.cvt8());
    code.seto(tmp2.cvt8());

    code.mov(tmp3, 0x8000000000000000);
    code.cmp(src2, tmp3);
    code.sete(src2.cvt8());
    code.xor(tmp2.cvt8(), src2.cvt8());

    code.mov(FlagState.flag_o_addr(code), tmp2.cvt8());
    code.or(FlagState.flag_os_addr(code), tmp2.cvt8());
    
    code.cmp(src2, 0);
    code.sete(src2.cvt8());
    code.or(tmp1.cvt8(), src2.cvt8());
    code.mov(FlagState.flag_c_addr(code), tmp1.cvt8());


    emit_set_flags_without_host_state(flags_to_set, code, result, tmp1);
}

private void emit_set_flags_without_host_state(int flags_to_set, DspCode code, R64 result, R64 tmp) {
    if (flags_to_set & Flag.S) {
        code.mov(tmp, result);
        code.sar(tmp, 63);
        code.mov(FlagState.flag_s_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.S32) {
        code.mov(tmp, 1L << 55);
        code.add(tmp, result);
        code.sar(tmp, 56);
        code.setne(tmp.cvt8());
        code.mov(FlagState.flag_s32_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.TB) {
        // top two bits equal
        code.mov(tmp, result); 
        code.shl(tmp, 1);
        code.xor(tmp, result);
        code.not(tmp);
        code.sal(tmp, 8);
        code.shr(tmp, 64 - 1);
        code.mov(FlagState.flag_tb_addr(code), tmp.cvt8());
    }

    if (flags_to_set & Flag.LZ) {
        // dunno yet lol
    }
}

void emit_reset_flags(DspCode code) {
    code.mov(FlagState.flag_c_addr(code), 0);
    code.mov(FlagState.flag_o_addr(code), 0);
    code.mov(FlagState.flag_az_addr(code), 1);
    code.mov(FlagState.flag_s_addr(code), 0);
    code.mov(FlagState.flag_s32_addr(code), 0);
    code.mov(FlagState.flag_tb_addr(code), 1);
}
