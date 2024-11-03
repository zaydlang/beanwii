module emu.hw.broadway.jit.emission.flags;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import xbyak;

// result could equal tmp1 if needed
void set_flags(Code code, bool rc, bool oe, Reg32 result, Reg32 tmp1, Reg32 tmp2, Reg32 tmp3) {
    code.setc(tmp2.cvt8());

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
        code.and(code.get_address(GuestReg.CR), 0xffff_fff0);
        code.or(code.get_address(GuestReg.CR), tmp1);
    }

    code.shl(tmp2, 29);
    code.and(code.get_address(GuestReg.XER), 0xdfff_ffff);
    code.or(code.get_address(GuestReg.XER), tmp2);
}