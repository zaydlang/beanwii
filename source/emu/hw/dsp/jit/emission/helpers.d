module emu.hw.dsp.jit.emission.helpers;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.flags;
import gallinule.x86;
import util.log;

void emit_wrapping_register_add(DspCode code, R16 ar, R16 wr, R16 ix, R16 sum) {
    R16 n    = code.allocate_register().cvt16();
    R16 mask = code.allocate_register().cvt16();
    R16 tmp  = code.allocate_register().cvt16();

    code.movzx(ix.cvt32(), ix);
    code.movzx(wr.cvt32(), wr);
    code.movzx(ar.cvt32(), ar);

    // source for this algorithm, the legendary duo:
    //    https://github.com/hrydgard for coming up with the initial algorithm     
    //    https://github.com/calc84maniac for refining it to this form

    // let N be the number of significant bits in WR, with a minimum of 1
    code.mov(n, wr);
    code.or(n, 1);
    code.bsr(n, n);
    code.add(n, 1);

    // create a mask out of N
    code.mov(mask, 1);
    code.mov(cl, n.cvt8());
    code.shl(mask.cvt32());
    code.sub(mask.cvt32(), 1);

    // let SUM be REG + IX...
    code.mov(sum.cvt32(), ar.cvt32());
    code.add(sum.cvt32(), ix.cvt32());

    // and let CARRY be the carry out of the low N bits of that addition
    R16 carry = ar;
    code.and(ar, mask);
    code.movzx(tmp.cvt32(), ix);
    code.and(tmp, mask);
    code.add(carry.cvt32(), tmp.cvt32());
    code.shr(carry.cvt32());
    code.and(carry, 1);

    // if IX >= 0 ...
    auto ix_negative = code.fresh_label();
    auto done = code.fresh_label();

    code.cmp(ix, 0);
    code.jl(ix_negative);

    // if CARRY == 1:
    code.cmp(carry, 0);
    code.je(done);

    // let SUM be SUM - WR - 1
    code.add(wr, 1);
    code.sub(sum, wr);
    code.jmp(done);

code.label(ix_negative);
    // if CARRY == 0 or the low N bits of SUM is less than the low N bits of ~WR:
    auto underflow = code.fresh_label();
    code.cmp(carry, 0);
    code.je(underflow);
    code.mov(tmp, wr);
    code.not(tmp);

    // reuse ix since it's no longer needed
    code.mov(ix, sum);
    code.and(ix, mask);
    code.and(tmp, mask);
    code.cmp(ix, tmp);
    code.jb(underflow);
    code.jmp(done);

code.label(underflow);
    // let SUM be SUM + (WR + 1)
    code.add(wr, 1);
    code.add(sum, wr);

code.label(done);

}

void emit_wrapping_register_sub(DspCode code, R16 ar, R16 wr, R16 ix, R16 sum) {
    R16 n    = code.allocate_register().cvt16();
    R16 mask = code.allocate_register().cvt16();
    R16 tmp  = code.allocate_register().cvt16();

    code.sub(ix.cvt32(), 1);

    code.movzx(ix.cvt32(), ix);
    code.movzx(wr.cvt32(), wr);
    code.movzx(ar.cvt32(), ar);

    // source for this algorithm, the legendary duo:
    //    https://github.com/hrydgard for coming up with the initial algorithm     
    //    https://github.com/calc84maniac for refining it to this form

    // let N be the number of significant bits in WR, with a minimum of 1
    code.mov(n, wr);
    code.or(n, 1);
    code.bsr(n, n);
    code.add(n, 1);

    // create a mask out of N
    code.mov(mask, 1);
    code.mov(cl, n.cvt8());
    code.shl(mask.cvt32());
    code.sub(mask.cvt32(), 1);

    // let SUM be REG + IX...
    code.mov(sum.cvt32(), ar.cvt32());
    code.add(sum.cvt32(), ix.cvt32());
    code.add(sum.cvt32(), 1);

    // and let CARRY be the carry out of the low N bits of that addition
    R16 carry = ar;
    code.and(ar, mask);
    code.movzx(tmp.cvt32(), ix);
    code.and(tmp.cvt32(), mask.cvt32());
    code.add(tmp.cvt32(), 1);
    code.add(carry.cvt32(), tmp.cvt32());
    code.shr(carry.cvt32());
    code.and(carry, 1);

    // if IX >= 0 ...
    auto ix_negative = code.fresh_label();
    auto done = code.fresh_label();

    code.add(ix.cvt32(), 1);
    code.cmp(ix, 0);
    code.jle(ix_negative);

    // if CARRY == 1:
    code.cmp(carry, 0);
    code.je(done);

    // let SUM be SUM - WR - 1
    code.add(wr, 1);
    code.sub(sum, wr);
    code.jmp(done);

code.label(ix_negative);
    // if CARRY == 0 or the low N bits of SUM is less than the low N bits of ~WR:
    auto underflow = code.fresh_label();
    code.cmp(carry, 0);
    code.je(underflow);
    code.mov(tmp, wr);
    code.not(tmp);

    // reuse ix since it's no longer needed
    code.mov(ix, sum);
    code.and(ix, mask);
    code.and(tmp, mask);
    code.cmp(ix, tmp);
    code.jb(underflow);
    code.jmp(done);

code.label(underflow);
    // let SUM be SUM + (WR + 1)
    code.add(wr, 1);
    code.add(sum, wr);

code.label(done);
}

void emit_wrapping_register_sub_one(DspCode code, R16 ar, R16 wr, R16 sum) {
    R32 nar = code.allocate_register().cvt32();
    R32 tmp1 = code.allocate_register().cvt32();
    R32 tmp2 = code.allocate_register().cvt32();

    code.movzx(nar, ar);
    code.add(nar, wr.cvt32());
    code.mov(tmp2, nar);

    code.xor(tmp2, ar.cvt32());
    code.movzx(tmp1, wr);
    code.or(tmp1, 1);
    code.shl(tmp1, 1);
    code.and(tmp2, tmp1);
    code.cmp(tmp2, wr.cvt32());

    auto no_wrap = code.fresh_label();
    code.jle(no_wrap);

    code.add(wr, 1);
    code.sub(nar, wr.cvt32());

code.label(no_wrap);
    code.mov(sum, nar.cvt16());
}

void emit_wrapping_register_add_one(DspCode code, R16 ar, R16 wr, R16 sum) {
    R32 nar = code.allocate_register().cvt32();
    R32 tmp1 = code.allocate_register().cvt32();
    R32 tmp2 = code.allocate_register().cvt32();

    code.movzx(nar, ar);
    code.add(nar, 1);
    code.mov(tmp2, nar);

    code.xor(tmp2, ar.cvt32());
    code.movzx(tmp1, wr);
    code.or(tmp1, 1);
    code.shl(tmp1, 1);
    code.cmp(tmp2, tmp1);

    auto no_wrap = code.fresh_label();
    code.jle(no_wrap);

    code.add(wr, 1);
    code.sub(nar, wr.cvt32());

code.label(no_wrap);
    code.mov(sum, nar.cvt16());
}

void read_arbitrary_reg(DspCode code, R64 result, int reg) {
    final switch (reg) {
        case 0: code.movzx(result.cvt32(), code.ar_address(0)); break;
        case 1: code.movzx(result.cvt32(), code.ar_address(1)); break;
        case 2: code.movzx(result.cvt32(), code.ar_address(2)); break;
        case 3: code.movzx(result.cvt32(), code.ar_address(3)); break;

        case 4: code.movzx(result.cvt32(), code.ix_address(0)); break;
        case 5: code.movzx(result.cvt32(), code.ix_address(1)); break;
        case 6: code.movzx(result.cvt32(), code.ix_address(2)); break;
        case 7: code.movzx(result.cvt32(), code.ix_address(3)); break;

        case 8: code.movzx(result.cvt32(), code.wr_address(0)); break;
        case 9: code.movzx(result.cvt32(), code.wr_address(1)); break;
        case 10: code.movzx(result.cvt32(), code.wr_address(2)); break;
        case 11: code.movzx(result.cvt32(), code.wr_address(3)); break;
    
        case 12: error_dsp("TODO: implement ST0 read"); break;
        case 13: error_dsp("TODO: implement ST1 read"); break;
        case 14: error_dsp("TODO: implement ST2 read"); break;
        case 15: error_dsp("TODO: implement ST3 read"); break;

        case 16: code.movsx(result.cvt32(), code.ac_hi_address_u8(0)); break;
        case 17: code.movsx(result.cvt32(), code.ac_hi_address_u8(1)); break;

        case 18: error_dsp("TODO: implement config read"); break;

        case 19:
            // lol
            R64 tmp1 = code.allocate_register();
            code.movzx(result.cvt32(), code.sr_upper_address());
            code.shl(result, 8);
            
            code.movzx(tmp1.cvt32(), FlagState.flag_c_addr(code));
            code.and(tmp1, 1);
            code.or(result.cvt32(), tmp1.cvt32());
    
            code.movzx(tmp1.cvt32(), FlagState.flag_o_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 1);
            code.or(result.cvt32(), tmp1.cvt32());

            code.movzx(tmp1.cvt32(), FlagState.flag_az_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 2);
            code.or(result.cvt32(), tmp1.cvt32());

            code.movzx(tmp1.cvt32(), FlagState.flag_s_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 3);
            code.or(result.cvt32(), tmp1.cvt32());

            code.movzx(tmp1.cvt32(), FlagState.flag_s32_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 4);
            code.or(result.cvt32(), tmp1.cvt32());

            code.movzx(tmp1.cvt32(), FlagState.flag_tb_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 5);
            code.or(result.cvt32(), tmp1.cvt32());

            code.movzx(tmp1.cvt32(), FlagState.flag_lz_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 6);
            code.or(result.cvt32(), tmp1.cvt32());

            code.movzx(tmp1.cvt32(), FlagState.flag_os_addr(code));
            code.and(tmp1, 1);
            code.shl(tmp1, 7);
            code.or(result.cvt32(), tmp1.cvt32());
            break;
        
        case 20: code.movzx(result.cvt32(), code.prod_lo_address()); break;
        case 21: code.movzx(result.cvt32(), code.prod_m1_address()); break;
        case 22: code.movzx(result.cvt32(), code.prod_hi_address_u8()); break;
        case 23: code.movzx(result.cvt32(), code.prod_m2_address()); break;

        case 24: code.movzx(result.cvt32(), code.ax_lo_address(0)); break;
        case 25: code.movzx(result.cvt32(), code.ax_lo_address(1)); break;

        case 26: code.movzx(result.cvt32(), code.ax_hi_address(0)); break;
        case 27: code.movzx(result.cvt32(), code.ax_hi_address(1)); break;

        case 28: code.movzx(result.cvt32(), code.ac_lo_address(0)); break;
        case 29: code.movzx(result.cvt32(), code.ac_lo_address(1)); break;

        case 30:
        case 31: {
            R64 sxm = code.allocate_register(); 
            code.movzx(result.cvt32(), code.ac_m_address(reg - 30));
            code.movzx(sxm.cvt32(), code.sr_upper_address());
            code.and(sxm, 0x40);

            auto no_sxm = code.fresh_label();

            code.cmp(sxm, 0);
            code.je(no_sxm);

            R64 ml_extended = code.allocate_register();
            R64 hml_extended = code.allocate_register();
            code.mov(ml_extended.cvt32(), code.ac_ml_address(reg - 30));
            code.sal(ml_extended, 64 - 32);
            code.sar(ml_extended, 64 - 32);
            code.mov(hml_extended, code.ac_full_address(reg - 30));
            code.sal(hml_extended, 64 - 40);
            code.sar(hml_extended, 64 - 40);

            auto is_sign_extended = code.fresh_label();
            code.cmp(ml_extended, hml_extended);
            code.je(is_sign_extended);

            code.cmp(hml_extended, 0);
            code.setl(result.cvt8());
            code.movzx(result.cvt32(), result.cvt8());
            code.add(result, 0x7fff);

        code.label(is_sign_extended);
        code.label(no_sxm);
            break;
        }
    }
}

void write_arbitrary_reg(DspCode code, R64 value, int reg) {
    final switch (reg) {
        case 0: code.mov(code.ar_address(0), value.cvt16()); break;
        case 1: code.mov(code.ar_address(1), value.cvt16()); break;
        case 2: code.mov(code.ar_address(2), value.cvt16()); break;
        case 3: code.mov(code.ar_address(3), value.cvt16()); break;

        case 4: code.mov(code.ix_address(0), value.cvt16()); break;
        case 5: code.mov(code.ix_address(1), value.cvt16()); break;
        case 6: code.mov(code.ix_address(2), value.cvt16()); break;
        case 7: code.mov(code.ix_address(3), value.cvt16()); break;

        case 8: code.mov(code.wr_address(0), value.cvt16()); break;
        case 9: code.mov(code.wr_address(1), value.cvt16()); break;
        case 10: code.mov(code.wr_address(2), value.cvt16()); break;
        case 11: code.mov(code.wr_address(3), value.cvt16()); break;
    
        case 12: error_dsp("TODO: implement ST0 write"); break;
        case 13: error_dsp("TODO: implement ST1 write"); break;
        case 14: error_dsp("TODO: implement ST2 write"); break;
        case 15: error_dsp("TODO: implement ST3 write"); break;

        case 16: code.mov(code.ac_hi_address(0), value.cvt16()); break;
        case 17: code.mov(code.ac_hi_address(1), value.cvt16()); break;

        case 18: error_dsp("TODO: implement config write"); break;

        case 19:
            // lol
            R64 tmp1 = code.allocate_register();
            R64 sr_upper = code.allocate_register();

            code.mov(sr_upper, value);
            code.shr(sr_upper, 8);
            code.and(sr_upper, ~1);
            code.mov(code.sr_upper_address(), sr_upper.cvt8());

            code.mov(tmp1, value);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_c_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 1);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_o_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 2);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_az_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 3);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_s_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 4);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_s32_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 5);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_tb_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 6);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_lz_addr(code), tmp1.cvt8());

            code.mov(tmp1, value);
            code.shr(tmp1, 7);
            code.and(tmp1, 1);
            code.mov(FlagState.flag_os_addr(code), tmp1.cvt8());
            break;
        
        case 20: code.mov(code.prod_lo_address(), value.cvt16()); break;
        case 21: code.mov(code.prod_m1_address(), value.cvt16()); break;
        case 22: code.mov(code.prod_hi_address(), value.cvt16()); break;
        case 23: code.mov(code.prod_m2_address(), value.cvt16()); break;

        case 24: code.mov(code.ax_lo_address(0), value.cvt16()); break;
        case 25: code.mov(code.ax_lo_address(1), value.cvt16()); break;

        case 26: code.mov(code.ax_hi_address(0), value.cvt16()); break;
        case 27: code.mov(code.ax_hi_address(1), value.cvt16()); break;

        case 28: code.mov(code.ac_lo_address(0), value.cvt16()); break;
        case 29: code.mov(code.ac_lo_address(1), value.cvt16()); break;

        case 30:
        case 31: {
            code.mov(code.ac_m_address(reg - 30), value.cvt16());
            auto sxm = code.allocate_register().cvt32();
            code.movzx(sxm, code.sr_upper_address());
            code.and(sxm, 0x40);
            
            auto no_sxm = code.fresh_label();
            code.cmp(sxm, 0);
            code.je(no_sxm);

            code.mov(sxm, 0);
            code.mov(code.ac_lo_address(reg - 30), sxm.cvt16());

            code.movsx(value.cvt32(), value.cvt16());
            code.sar(value, 16);
            code.mov(code.ac_hi_address(reg - 30), value.cvt16());
        
        code.label(no_sxm);
            break;
        }
    }
}