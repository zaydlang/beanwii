module emu.hw.broadway.jit.emission.helpers;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.return_value;
import gallinule.x86;
import util.bitop;
import util.number;

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
    return 31 - cr_bit;
}

void is_cond_ok(Code code, int bo, int bi, R32 result) {
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
        code.shr(cr, cast(u8) cr_bit);
        code.and(cr, 1);
    
        if (cr_should_be) {
            code.and(result, cr);
        } else {
            code.not(cr);
            code.and(result, cr);
        }
    }
}

void abort(Code code) {
    code.xor(rdi, rdi);
    code.mov(rdi, code.qwordPtr(rdi));
}

void check_fp_enabled_or_jump(Code code) {
    if (code.has_checked_fp()) {
        return;
    }
    
    code.mark_fp_checked();
    
    auto msr = code.allocate_register_prefer(r15d);
    auto offset = get_reg_offset(GuestReg.MSR);
    code.mov(msr, code.dwordPtr(code.CPU_BASE_REG, cast(int) offset));
    
    code.test(msr, 1 << 13);

    auto fp_enabled_label = code.fresh_label();
    code.jnz(fp_enabled_label);
    
    code.set_reg(GuestReg.PC, code.get_guest_pc());
    code.mov(rax, BlockReturnValue.FloatingPointUnavailable);
    code.jmp(code.get_epilogue_label());

    code.label(fp_enabled_label);
}