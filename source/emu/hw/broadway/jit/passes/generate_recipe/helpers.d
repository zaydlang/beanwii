module emu.hw.broadway.jit.frontend.helpers;

import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.frontend.helpers;
import emu.hw.broadway.jit.frontend.opcode;
import emu.hw.broadway.jit.ir.ir;
import std.sumtype;
import util.bitop;
import util.log;
import util.number;

public void emit_add_generic(IR* ir, GuestReg rd, IRVariable op1, IRVariable op2, bool rc, bool affect_ca, bool affect_so_ov) {
    IRVariable result = op1 + op2;
    
    IRVariable carry    = ir.get_carry();
    IRVariable overflow = ir.get_overflow();

    ir.set_reg(rd, result);

    if (rc) {
        emit_set_cr_lt(ir, 0, result.lesser_signed(ir.constant(0)));
        emit_set_cr_gt(ir, 0, result.greater_signed(ir.constant(0)));
        emit_set_cr_eq(ir, 0, result.equals(ir.constant(0)));
        emit_set_cr_so(ir, 0, overflow);
    }

    if (affect_ca) {
        emit_set_xer_ca(ir, carry);
    }

    if (affect_so_ov) {
        assert(0);
    }
}

public void emit_cmp_generic(IR* ir, IRVariable op1, IRVariable op2, int crf_d, bool signed) {
    if (signed) {
        emit_set_cr_gt(ir, crf_d, op1.greater_signed(op2));
        emit_set_cr_lt(ir, crf_d, op1.lesser_signed(op2));
    } else {
        emit_set_cr_gt(ir, crf_d, op1.greater_unsigned(op2));
        emit_set_cr_lt(ir, crf_d, op1.lesser_unsigned(op2));
    }

    emit_set_cr_eq(ir, crf_d, op1.equals(op2));
    emit_set_cr_so(ir, crf_d, emit_get_xer_so(ir));
}

public void emit_set_cr_flags_generic(IR* ir, int field, IRVariable var) {
    emit_set_cr_lt(ir, field, var.lesser_signed(ir.constant(0)));
    emit_set_cr_gt(ir, field, var.greater_signed(ir.constant(0)));
    emit_set_cr_eq(ir, field, var.equals(ir.constant(0)));
    emit_set_cr_so(ir, field, emit_get_xer_so(ir));
}

public int generate_rlw_mask(int mb, int me) {
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

public IRVariable emit_evaluate_condition(IR* ir, int bo, int bi) {
    IRVariable cond_ok() {
        IRVariable cr = ir.get_reg(GuestReg.CR);
        return ((cr >> (31 - bi)) & 1);
    }

    IRVariable ctr_ok() {
        IRVariable ctr = ir.get_reg(GuestReg.CTR);
        ctr = ctr - 1;
        ir.set_reg(GuestReg.CTR, ctr);

        return ctr.equals(ir.constant(0));
    }

    final switch (bo >> 2) {
        case 0b000:
            if (bo.bit(1)) {
                return ctr_ok() & (cond_ok() ^ 1);
            } else {
                return (ctr_ok() ^ 1) & (cond_ok() ^ 1);
            }

        case 0b010:
            if (bo.bit(1)) {
                return ctr_ok() & cond_ok();
            } else {
                return (ctr_ok() ^ 1) & cond_ok();
            }

        case 0b100:
        case 0b110:
            if (bo.bit(1)) {
                return ctr_ok();
            } else {
                return ctr_ok() ^ 1;
            }

        case 0b101:
        case 0b111:
            return ir.constant(1);
        
        case 0b001: // if condition is false
            return cond_ok() ^ 1;

        case 0b011: // if condition is true
            return cond_ok();
    }
}

private void emit_set_cr_flag(IR* ir, int field, int bit, IRVariable value) {
    int index = (7 - field) * 4 + bit;

    // SO is sticky
    bool sticky = bit == 0;
    
    IRVariable cr = ir.get_reg(GuestReg.CR);
    if (!sticky) cr = cr & ~(1 << index);
    cr = cr |  (value << index);
    ir.set_reg(GuestReg.CR, cr);
}

public void emit_set_cr_lt(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 3, value);
}

public void emit_set_cr_gt(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 2, value);
}

public void emit_set_cr_eq(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 1, value);
}

public void emit_set_cr_so(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 0, value);
}

public IRVariable emit_get_xer_ca(IR* ir) {
    IRVariable xer = ir.get_reg(GuestReg.XER);
    return (xer >> 29) & 1;
}

public IRVariable emit_get_xer_so(IR* ir) {
    IRVariable xer = ir.get_reg(GuestReg.XER);
    return (xer >> 31) & 1;
}

public void emit_set_xer_ca(IR* ir, IRVariable value) {
    IRVariable xer = ir.get_reg(GuestReg.XER);
    xer = xer &  ~(1     << 29);
    xer = xer |   (value << 29);
    ir.set_reg(GuestReg.XER, xer);
}

public void emit_set_xer_so_ov(IR* ir, IRVariable value) {
    IRVariable xer = ir.get_reg(GuestReg.XER);
    xer = xer &  ~(1           << 30);
    xer = xer |   ((value * 3) << 30);
    ir.set_reg(GuestReg.XER, xer);
}

public GuestReg get_spr_from_encoding(int encoding) {
    switch (encoding) {
        case 9:    return GuestReg.CTR;
        case 8:    return GuestReg.LR;
        case 1:    return GuestReg.XER;
        case 26:   return GuestReg.SRR0;
        case 912:  return GuestReg.GQR0;
        case 913:  return GuestReg.GQR1;
        case 914:  return GuestReg.GQR2;
        case 915:  return GuestReg.GQR3;
        case 916:  return GuestReg.GQR4;
        case 917:  return GuestReg.GQR5;
        case 918:  return GuestReg.GQR6;
        case 919:  return GuestReg.GQR7;
        case 1008: return GuestReg.HID0;
        case 920:  return GuestReg.HID2;
        case 1011: return GuestReg.HID4;
        case 1017: return GuestReg.L2CR;
        case 952:  return GuestReg.MMCR0;
        case 956:  return GuestReg.MMCR1;
        case 953:  return GuestReg.PMC1;
        case 954:  return GuestReg.PMC2;
        case 957:  return GuestReg.PMC3;
        case 958:  return GuestReg.PMC4;

        default: 
            error_broadway("Unknown SPR: %d (0x%x)", encoding, encoding);
            assert(0);
    }
}