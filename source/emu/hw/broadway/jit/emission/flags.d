module emu.hw.broadway.jit.emission.flags;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import xbyak;

void set_flags(Code code, bool rc, bool oe, Reg32 tmp1, Reg32 tmp2, Reg32 tmp3) {
    code.setc(tmp2.cvt8());

    if (oe) {
        code.seto(tmp3.cvt8());
    }

    if (rc) {
        // Thanks MerryMage for the following trick:
        //               x64 flags    
        //               ZF  PF  CF     My Flags
        // Greater than   0   0   0       100
        // Less than      0   0   1       010
        // Equal          1   0   0       001
        // Unordered      1   1   1       000
        //
        // Thus we can take use ZF:CF as an index into an array like so:
        //  x64      My Flags
        // ZF:CF     
        //   0       1000'0000'0000'0000 = 0x8000
        //   1       0100'0000'0000'0000 = 0x4000
        //   2       0010'0000'0000'0000 = 0x2000
        //   3       0000'0000'0000'0000 = 0x0000f

        code.sete(cl);
        code.rcl(cl, 5); // cl = ZF:CF:0000

        code.mov(tmp1, 0x0000_0002_0004_0008);
        code.shr(tmp1, cl);
        code.and(tmp1, 0xffff);

        code.seto(cl);
        code.or(tmp1, rcx);

        code.and(code.get_address(GuestReg.CR), 0xffff_fff0);
        code.or(code.get_address(GuestReg.CR), tmp1);
    }

    if (oe) {
        code.lea(tmp3, dword [tmp3 + tmp3 * 2]);
        code.shl(tmp3, 30);
        code.and(code.get_address(GuestReg.XER), 0xbfff_ffff);
        code.or(code.get_address(GuestReg.XER), tmp3);
    }

    code.shl(tmp2, 29);
    code.and(code.get_address(GuestReg.XER), 0xdfff_ffff);
    code.or(code.get_address(GuestReg.XER), tmp2);
}