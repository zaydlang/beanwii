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
        emit_set_cr_lt(ir, 0, result.lesser (op1));
        emit_set_cr_gt(ir, 0, result.greater(op1));
        emit_set_cr_eq(ir, 0, result.equals (op1));
        emit_set_cr_so(ir, 0, overflow);
    }

    if (affect_ca) {
        emit_set_xer_ca(ir, carry);
    }

    if (affect_so_ov) {
        assert(0);
    }
}

public IRVariable emit_evaluate_condition(IR* ir, int bo, int bi) {
    log_jit("jit BO: %x %x", bo, bi);
    final switch (bo >> 2) {
        case 0b000:
        case 0b010:
        case 0b100:
        case 0b110:
            assert(0);

        case 0b101:
        case 0b111:
            return ir.constant(1);
        
        case 0b001: // if condition is false
            IRVariable cr = ir.get_reg(GuestReg.CR);
            return ((cr >> bi) & 1).notequals(ir.constant(bo.bit(1)));

        case 0b011: // if condition is true
            IRVariable cr = ir.get_reg(GuestReg.CR);
            return ((cr >> bi) & 1).equals(ir.constant(bo.bit(1)));
    }
}

private void emit_set_cr_flag(IR* ir, int field, int bit, IRVariable value) {
    int index = field * 4 + bit;
    
    IRVariable cr = ir.get_reg(GuestReg.CR);
    cr = cr & ~(1 << index);
    cr = cr | value;
    ir.set_reg(GuestReg.CR, cr);
}

public void emit_set_cr_lt(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 0, value);
}

public void emit_set_cr_gt(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 1, value);
}

public void emit_set_cr_eq(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 2, value);
}

public void emit_set_cr_so(IR* ir, int field, IRVariable value) {
    emit_set_cr_flag(ir, field, 3, value);
}

public void emit_set_xer_ca(IR* ir, IRVariable value) {
    IRVariable xer = ir.get_reg(GuestReg.XER);
    xer = xer &  ~(1     << 2);
    xer = xer |   (value << 2);
    ir.set_reg(GuestReg.XER, xer);
}
