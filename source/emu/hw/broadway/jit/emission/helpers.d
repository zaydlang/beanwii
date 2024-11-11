module emu.hw.broadway.jit.emission.helpers;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import util.bitop;
import util.number;
import xbyak;

u32 generate_rlw_mask(u32 mb, u32 me) {
    // i hate this entire function

    int i = mb;
    int mask = 0;
    while (i != me) {
        mask |= (1 << (31 - i));
        i = (i + 1) & 0x1F;
    } 
    mask |= (1 << (31 - i));

    return mask;
}

int get_cr_index(int cr_bit) {
    // account for powerpc having the bits in the opposite order
    return 3 - (cr_bit & 3) + 4 * (cr_bit >> 2);
}

void is_cond_ok(Code code, int bo, int bi, Reg32 result) {
    bool should_decrement_ctr = !bo.bit(2);
    bool should_check_cr      = !bo.bit(4);
    bool ctr_should_be        =  bo.bit(1);
    bool cr_should_be         =  bo.bit(3);

    int cr_bit = get_cr_index(bi);

    if (should_decrement_ctr) {
        auto ctr = code.get_reg(GuestReg.CTR);
        code.sub(ctr, 1);
        code.set_reg(GuestReg.CTR, ctr);
    
        if (ctr_should_be) {
            code.sete(result.cvt8());
        } else {
            code.setne(result.cvt8());
        }
    } else {
        code.mov(result, 1);
    }

    if (should_check_cr) {
        auto cr = code.get_reg(GuestReg.CR);
        code.shr(cr, cr_bit);
        code.and(cr, 1);
    
        if (cr_should_be) {
            code.and(result, cr);
        } else {
            code.not(cr);
            code.and(result, cr);
        }
    }
}