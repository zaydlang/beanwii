module emu.hw.broadway.jit.frontend.floating_point;

import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.frontend.helpers;
import emu.hw.broadway.jit.ir.ir;
import util.bitop;
import util.log;
import util.number;

public IRVariable emit_get_hid2_pse(IR* ir) {
    return (ir.get_reg(GuestReg.HID2) >> 29) & 1;
}

public void emit_fabsx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(16, 20) == 0b11110);

    ir.set_reg(rd, ir.get_reg(rb).abs());
}

public void emit_faddx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(1, 5) == 0b11110);

    ir.set_reg(rd, ir.get_reg(ra) + ir.get_reg(rb));
}

public void emit_fmsubx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    IRVariable dest = ir.get_reg(ra) * ir.get_reg(rc) - ir.get_reg(rb);
    ir.set_fpscr(dest);
    ir.set_reg(rd, dest);
}

public void emit_fmulx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    ir.set_reg(rd, ir.get_reg(ra) * ir.get_reg(rc));
}

public void emit_fnegx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    ir.set_reg(rd, -ir.get_reg(rb));
}

public void emit_fnmsubsx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_ps(opcode.bits(21, 25));
    GuestReg ra = to_ps(opcode.bits(16, 20));
    GuestReg rb = to_ps(opcode.bits(11, 15));
    GuestReg rc = to_ps(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    assert(opcode.bits(1, 5) == 0b11110);

    ir.set_reg(rd, -(ir.get_reg(ra) * ir.get_reg(rc) - ir.get_reg(rb)));
}

public void emit_fnabsx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_ps(opcode.bits(21, 25));
    GuestReg rb = to_ps(opcode.bits(11, 15));

    assert(opcode.bits(16, 20) == 0b00000);

    ir.set_reg(rd, -ir.get_reg(rb).abs());
}

public void emit_fsel(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    IRVariable dest = ir.get_reg(rc);
    ir._if(ir.get_reg(ra).lesser_signed(ir.constant(0.0f)), {
        dest = ir.get_reg(rb);
    });

    ir.set_reg(rd, dest);
}