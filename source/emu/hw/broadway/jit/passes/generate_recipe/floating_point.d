module emu.hw.broadway.jit.passes.generate_recipe.floating_point;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.jit;
import emu.hw.broadway.jit.passes.generate_recipe.helpers;
import util.bitop;
import util.log;
import util.number;

public IRVariable emit_get_hid2_pse(IR* ir) {
    return (ir.get_reg(GuestReg.HID2) >> 29) & 1;
}

public void emit_fabsx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(16, 20) == 0);

    ir.set_reg(rd, ir.get_reg(rb).abs());
}

public void emit_faddsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    int op_d = opcode.bits(21, 25);
    
    bool record = opcode.bit(0);

    assert(opcode.bits(6, 10) == 0);
    
    IRVariable result = ir.get_reg(to_ps0(op_a)) + ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_faddx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(6, 10) == 0);

    ir.set_reg(rd, ir.get_reg(ra) + ir.get_reg(rb));
}

public void emit_fctiwx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(16, 20) == 0);

    // ir.set_reg(rd, result.to_saturated_int());
}

public void emit_fdivsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_d = opcode.bits(21, 25);
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    bool record = opcode.bit(0);

    assert(opcode.bits(6, 10) == 0);

    IRVariable result = ir.get_reg(to_ps0(op_a)) / ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fdivx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(6, 10) == 0);

    ir.set_reg(rd, ir.get_reg(ra) / ir.get_reg(rb));
}

public void emit_fmaddsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    int op_c = opcode.bits(6, 10);
    int op_d = opcode.bits(21, 25);
    
    bool record = opcode.bit(0);

    IRVariable result = ir.get_reg(to_ps0(op_a)) * ir.get_reg(to_ps0(op_c)) + ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fmaddx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    IRVariable dest = ir.get_reg(ra) * ir.get_reg(rc) + ir.get_reg(rb);
    ir.set_fpscr(dest);
    ir.set_reg(rd, dest);
}

public void emit_fmr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    assert(opcode.bits(16, 20) == 0);

    ir.set_reg(rd, ir.get_reg(rb));
}

public void emit_fmsubsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    int op_c = opcode.bits(6, 10);
    int op_d = opcode.bits(21, 25);
    
    bool record = opcode.bit(0);

    IRVariable result = ir.get_reg(to_ps0(op_a)) * ir.get_reg(to_ps0(op_c)) - ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fmsubx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    IRVariable dest = ir.get_reg(ra) * ir.get_reg(rc) - ir.get_reg(rb);
    ir.set_fpscr(dest);
    ir.set_reg(rd, dest);
}

public void emit_fmulsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(6,  10);
    int op_d = opcode.bits(21, 25);
    bool record = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(to_ps0(op_a)) * ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fmulx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    ir.set_reg(rd, ir.get_reg(ra) * ir.get_reg(rc));
}

public void emit_fnegx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    bool record = opcode.bit(0);

    ir.set_reg(rd, -ir.get_reg(rb));
}

public void emit_fnmaddsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    int op_c = opcode.bits(6, 10);
    int op_d = opcode.bits(21, 25);
    
    bool record = opcode.bit(0);

    IRVariable result = -(ir.get_reg(to_ps0(op_a)) * ir.get_reg(to_ps0(op_c)) + ir.get_reg(to_ps0(op_b)));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fnmaddx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    IRVariable dest = -(ir.get_reg(ra) * ir.get_reg(rc) + ir.get_reg(rb));
    ir.set_fpscr(dest);
    ir.set_reg(rd, dest);
}

public void emit_fnmsubsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    int op_c = opcode.bits(6, 10);
    int op_d = opcode.bits(21, 25);
    
    bool record = opcode.bit(0);

    IRVariable result = -(ir.get_reg(to_ps0(op_a)) * ir.get_reg(to_ps0(op_c)) - ir.get_reg(to_ps0(op_b)));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fnmsubx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_fpr(opcode.bits(16, 20));
    GuestReg rb = to_fpr(opcode.bits(11, 15));
    GuestReg rc = to_fpr(opcode.bits(6,  10));
    bool record = opcode.bit(0);

    IRVariable dest = -(ir.get_reg(ra) * ir.get_reg(rc) - ir.get_reg(rb));
    ir.set_fpscr(dest);
    ir.set_reg(rd, dest);
}

public void emit_fnabsx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg rb = to_fpr(opcode.bits(11, 15));

    assert(opcode.bits(16, 20) == 0b00000);

    ir.set_reg(rd, -ir.get_reg(rb).abs());
}

public void emit_fresx(IR* ir, u32 opcode, JitContext ctx) {
    int op_b = opcode.bits(11, 15);
    int op_d = opcode.bits(21, 25);
    bool record = opcode.bit(0);

    assert(opcode.bits(16, 20) == 0b00000);
    assert(opcode.bits(6,  10) == 0b00000);

    IRVariable result = ir.constant(1.0f) / ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_fsel(IR* ir, u32 opcode, JitContext ctx) {
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

public void emit_fsubsx(IR* ir, u32 opcode, JitContext ctx) {
    int op_a = opcode.bits(16, 20);
    int op_b = opcode.bits(11, 15);
    int op_d = opcode.bits(21, 25);
    bool record = opcode.bit(0);

    assert(opcode.bits(6, 10) == 0b00000);

    IRVariable result = ir.get_reg(to_ps0(op_a)) - ir.get_reg(to_ps0(op_b));
    ir.set_reg(to_ps0(op_d), result);
    if (ctx.pse) {
        ir.set_reg(to_ps1(op_d), result);
    }
}

public void emit_mftsb1(IR* ir, u32 opcode, JitContext ctx) {
    int bit = opcode.bits(21, 25);
    bool record = opcode.bit(0);

    assert(opcode.bits(16, 20) == 0b00000);
    assert(opcode.bits(11, 15) == 0b00000);

    // what does this bit even mean in this opcode????
    assert(!record);

    ir.set_reg(GuestReg.FPSCR, ir.get_reg(GuestReg.FPSCR) | ir.constant(1 << bit));
}