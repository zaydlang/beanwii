module emu.hw.broadway.jit.emission.flags;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import util.log;
import xbyak;

enum CmpType {
    Unsigned,
    Signed
};

void do_cmp(T)(Code code, CmpType cmp_type, Reg32 lhs, T rhs, int cr) {
    static if (is(T == Reg32)) {
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
    code.shr(tmp, 31);
    code.or(lhs, tmp);
    code.shl(lhs, cr * 4);
    code.and(code.get_address(GuestReg.CR), ~(0xf << (cr * 4)));
    code.or(code.get_address(GuestReg.CR), lhs);
}

// result could equal tmp1 if needed
void set_flags(Code code, bool set_xer_carry, bool rc, bool oe, Reg32 result, Reg32 tmp1, Reg32 tmp2, Reg32 tmp3, int cr) {
    if (set_xer_carry) {
        code.setc(tmp2.cvt8());
    }

    if (oe) {
        code.seto(tmp3.cvt8());
    }

    if (oe) {
        code.lea(tmp3, dword [tmp3 + tmp3 * 2]);
        code.shl(tmp3, 30);
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
        code.shr(tmp3, 31);
        code.or(tmp1, tmp3);
        code.shl(tmp1, cr * 4);
        code.and(code.get_address(GuestReg.CR), ~(0xf << (cr * 4)));
        code.or(code.get_address(GuestReg.CR), tmp1);
    }

    if (set_xer_carry) {
        code.shl(tmp2, 29);
        code.and(code.get_address(GuestReg.XER), 0xdfff_ffff);
        code.or(code.get_address(GuestReg.XER), tmp2);
    }
}