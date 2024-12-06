module emu.hw.broadway.jit.emission.flags;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import gallinule.x86;
import util.log;
import util.number;

enum CmpType {
    Unsigned,
    Signed
};

void do_cmp(T)(Code code, CmpType cmp_type, R32 lhs, T rhs, int cr) {
    static if (is(T == R32)) {
        auto tmp = rhs;
    } else {
        auto tmp = code.allocate_register();
    }
    
    // repeated code, sue me
    code.cmp(lhs, rhs);
    code.mov(tmp, 8);

    final switch (cmp_type) {
        case CmpType.Unsigned:
            code.cmovb(lhs, tmp);
            code.mov(tmp, 4);
            code.cmova(lhs, tmp);
            break;
        case CmpType.Signed:
            code.cmovl(lhs, tmp);
            code.mov(tmp, 4);
            code.cmovg(lhs, tmp);
            break;
    }

    code.mov(tmp, 2);
    code.cmove(lhs, tmp);

    code.mov(tmp, code.get_address(GuestReg.XER));
    code.shr(tmp, cast(u8) 31);
    code.or(lhs, tmp);
    code.shl(lhs, cast(u8) (cr * 4));
    code.and(code.get_address(GuestReg.CR), ~(0xf << (cr * 4)));
    code.or(code.get_address(GuestReg.CR), lhs);
}

void set_division_flags(Code code, bool rc, bool oe, R32 tmp1, R32 tmp3, bool bad_division) {
    if (oe) {
        if (bad_division) {
            code.or(code.get_address(GuestReg.XER), 0xc000_0000);
        } else {
            code.and(code.get_address(GuestReg.XER), 0xbfff_ffff);
        }
    }

    if (rc) {
        if (bad_division) {
            code.cmp(eax, 0);
            code.mov(tmp3, 8);
            code.cmovl(tmp1, tmp3);
            code.mov(tmp3, 4);
            code.cmovg(tmp1, tmp3);
            code.mov(tmp3, 2);
            code.cmove(tmp1, tmp3);
        } else {
            code.cmp(eax, 0);
            code.mov(tmp3, 8 | 16);
            code.cmovl(tmp1, tmp3);
            code.mov(tmp3, 4 | 16);
            code.cmovg(tmp1, tmp3);
            code.mov(tmp3, 2 | 16);
            code.cmove(tmp1, tmp3);
        }

        code.and(code.get_address(GuestReg.CR), 0xffff_fff0);
        code.or(code.get_address(GuestReg.CR), tmp1);
    }
}

// result could equal tmp1 if needed
void set_flags(Code code, bool set_xer_carry, bool rc, bool oe, R32 result, R32 tmp1, R32 tmp2, R32 tmp3, int cr) {
    if (set_xer_carry) {
        code.setc(tmp2.cvt8());
    }

    if (oe) {
        code.seto(tmp3.cvt8());
    }

    if (oe) {
        code.mov(tmp1, tmp3);
        code.add(tmp1, tmp3);
        code.add(tmp3, tmp1);
        code.shl(tmp3, cast(u8) 30);
        code.and(code.get_address(GuestReg.XER), 0xbfff_ffff);
        code.or(code.get_address(GuestReg.XER), tmp3);
    }

    if (rc) {
        code.cmp(result, 0);
        code.mov(tmp3, 8);
        code.cmovl(tmp1, tmp3);
        code.mov(tmp3, 4);
        code.cmovg(tmp1, tmp3);
        code.mov(tmp3, 2);
        code.cmove(tmp1, tmp3);

        code.mov(tmp3, code.get_address(GuestReg.XER));
        code.shr(tmp3, cast(u8) 31);
        code.or(tmp1, tmp3);
        code.shl(tmp1, cast(u8) (cr * 4));
        code.and(code.get_address(GuestReg.CR), ~(0xf << (cr * 4)));
        code.or(code.get_address(GuestReg.CR), tmp1);
    }

    if (set_xer_carry) {
        code.shl(tmp2, cast(u8) 29);
        code.and(code.get_address(GuestReg.XER), 0xdfff_ffff);
        code.or(code.get_address(GuestReg.XER), tmp2);
    }
}

void emit_fp_flags_helper(Code code, int crfd, R32 tmp) {
    // thanks merryhime
    code.sete(cl);
    code.rcl(cl, 5);  // cl = ZF:CF:0000

    code.mov(tmp.cvt64(), 0x0000_2000_8000_4000);
    code.shr(tmp.cvt64());
    code.and(tmp, 0xffff);
    code.shr(tmp, 12);

    auto cr = code.get_reg(GuestReg.CR);
    code.and(cr, ~(0xf << (crfd * 4)));
    code.shl(tmp, cast(u8) (crfd * 4));
    code.or(cr, tmp);
    code.set_reg(GuestReg.CR, cr);
}