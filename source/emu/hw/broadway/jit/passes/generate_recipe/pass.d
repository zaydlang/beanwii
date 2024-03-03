module emu.hw.broadway.jit.passes.generate_recipe.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.jit;
import emu.hw.broadway.jit.passes.generate_recipe.floating_point;
import emu.hw.broadway.jit.passes.generate_recipe.helpers;
import emu.hw.broadway.jit.passes.generate_recipe.opcode;
import emu.hw.broadway.jit.passes.generate_recipe.paired_single;
import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.log;
import util.number;

alias IRVariable = IRVariableGenerator;

enum MAX_GUEST_OPCODES_PER_RECIPE = 20;

enum GenerateRecipeAction {
    STOP,
    CONTINUE,
}

private GenerateRecipeAction emit_addcx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     oe = opcode.bit(10);
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(ra) + ir.get_reg(rb);
    IRVariable carry    = ir.get_carry();
    IRVariable overflow = ir.get_overflow();

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addex(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     oe = opcode.bit(10);
    bool     rc = opcode.bit(0);

    IRVariable operand = ir.get_reg(rb) + emit_get_xer_ca(ir);
    IRVariable carry = ir.get_carry();
    IRVariable result = ir.get_reg(ra) + operand;
    IRVariable overflow = ir.get_overflow();
    carry = ir.get_carry() | carry;

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addi(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm = sext_32(opcode.bits(0, 15), 16);

    if (ra == 0) {
        ir.set_reg(rd, simm);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + simm);
    }

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addic(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm = sext_32(opcode.bits(0, 15), 16);

    emit_add_generic(
        ir,
        rd, ir.get_reg(ra), ir.constant(simm),
        false, // record bit
        true,  // XER CA
        false, // XER SO & OV
    );

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addic_(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd   = to_gpr(opcode.bits(21, 25));
    GuestReg ra   = to_gpr(opcode.bits(16, 20));
    int      simm = sext_32(opcode.bits(0, 15), 16);

    emit_add_generic(
        ir,
        rd, ir.get_reg(ra), ir.constant(simm),
        true,  // record bit
        true,  // XER CA
        false, // XER SO & OV
    );

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addis(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm = opcode.bits(0, 15); // no need to sext cuz it gets shifted by 16

    if (ra == 0) {
        ir.set_reg(rd, simm << 16);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + (simm << 16));
    }

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addmex(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    IRVariable result = ir.get_reg(ra) + (emit_get_xer_ca(ir) - 1);
    IRVariable carry    = ir.get_carry();
    IRVariable overflow = ir.get_overflow();

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     oe = opcode.bit(10);
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(ra) + ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_addzex(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    IRVariable result = ir.get_reg(ra) + emit_get_xer_ca(ir);
    IRVariable carry    = ir.get_carry();
    IRVariable overflow = ir.get_overflow();

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_and(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) & ir.get_reg(rb);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_andc(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) & ~ir.get_reg(rb);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_andi(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) & uimm;
    ir.set_reg(ra, result);

    emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_andis(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) & (uimm << 16);
    ir.set_reg(ra, result);

    emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.STOP;
}

private GenerateRecipeAction emit_b(IR* ir, u32 opcode, JitContext ctx) {
    bool aa = opcode.bit(1);
    bool lk = opcode.bit(0);
    int  li = opcode.bits(2, 25);

    u32 branch_address = sext_32(li, 24) << 2;
    if (!aa) branch_address += ctx.pc;

    if (lk) ir.set_reg(GuestReg.LR, ctx.pc + 4);

    // if (branch_address == ctx.pc) error_broadway("branch to self");

    ir.set_reg(GuestReg.PC, branch_address);

    return GenerateRecipeAction.STOP;
}

private GenerateRecipeAction emit_bc(IR* ir, u32 opcode, JitContext ctx) {
    bool lk = opcode.bit(0);
    bool aa = opcode.bit(1);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);
    int  bd = opcode.bits(2, 15);

    IRVariable cond = emit_evaluate_condition(ir, bo, bi);

    if (lk) {
        u32 address = aa ? ctx.pc + 4 + (sext_32(bd, 14) << 2) : sext_32(bd, 14) << 2;
        ir.branch_with_link(cond, ctx.pc + 4, ir.constant(address), ir.constant(ctx.pc) + 4);
    } else {
        ir.branch(cond, ir.constant(ctx.pc + (sext_32(bd, 14) << 2)), ir.constant(ctx.pc) + 4);
    }

    return GenerateRecipeAction.STOP;
}

private GenerateRecipeAction emit_bcctr(IR* ir, u32 opcode, JitContext ctx) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    assert(opcode.bits(11, 15) == 0);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    if (lk) {
        ir.branch_with_link(cond_ok, ctx.pc + 4, ir.get_reg(GuestReg.CTR), ir.constant(ctx.pc) + 4);
    } else {
        ir.branch(cond_ok, ir.get_reg(GuestReg.CTR), ir.constant(ctx.pc));
    }

    return GenerateRecipeAction.STOP;
}

private GenerateRecipeAction emit_bclr(IR* ir, u32 opcode, JitContext ctx) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    if (lk) {
        ir.branch_with_link(cond_ok, ctx.pc + 4, ir.get_reg(GuestReg.LR), ir.constant(ctx.pc) + 4);
    } else {
        ir.branch(cond_ok, ir.get_reg(GuestReg.LR), ir.constant(ctx.pc) + 4);
    }

    return GenerateRecipeAction.STOP;
}

private GenerateRecipeAction emit_cntlzw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).clz();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_cmp(IR* ir, u32 opcode, JitContext ctx) {
    int crf_d = opcode.bits(23, 25);
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0)  == 0);
    assert(opcode.bit(22) == 0);

    IRVariable a = ir.get_reg(ra);
    IRVariable b = ir.get_reg(rb);

    emit_cmp_generic(
        ir,
        a,
        b,
        crf_d,
        true
    );

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_cmpl(IR* ir, u32 opcode, JitContext ctx) {
    int crf_d = opcode.bits(23, 25);
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0)  == 0);
    assert(opcode.bit(22) == 0);

    IRVariable a = ir.get_reg(ra);
    IRVariable b = ir.get_reg(rb);

    emit_cmp_generic(
        ir,
        a,
        b,
        crf_d,
        false
    );

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_cmpli(IR* ir, u32 opcode, JitContext ctx) {
    int  crf_d = opcode.bits(23, 25);
    int  uimm  = opcode.bits(0, 15);

    assert(opcode.bit(22) == 0);

    GuestReg ra = to_gpr(opcode.bits(16, 20));
    IRVariable a = ir.get_reg(ra);

    emit_cmp_generic(
        ir,
        a,
        ir.constant(uimm),
        crf_d,
        false
    );

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_cmpi(IR* ir, u32 opcode, JitContext ctx) {
    int crf_d    = opcode.bits(23, 25);
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm    = sext_32(opcode.bits(0, 15), 16);

    assert(opcode.bit(22) == 0);

    IRVariable a = ir.get_reg(ra);

    emit_cmp_generic(
        ir,
        a,
        ir.constant(simm),
        crf_d,
        true
    );

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_crxor(IR* ir, u32 opcode, JitContext ctx) {
    int crbD = 31 - opcode.bits(21, 25);
    int crbA = 31 - opcode.bits(16, 20);
    int crbB = 31 - opcode.bits(11, 15);

    assert(opcode.bit(0) == 0);

    IRVariable cr = ir.get_reg(GuestReg.CR);
    cr = cr & ~(1 << crbD);
    cr = cr | ((((cr >> crbA) & 1) ^ ((cr >> crbB) & 1)) << crbD);
    ir.set_reg(GuestReg.CR, cr);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_dcbf(IR* ir, u32 opcode, JitContext ctx) {
    // i'm just not going to emulate cache stuff

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_dcbi(IR* ir, u32 opcode, JitContext ctx) {
    // i'm just not going to emulate cache stuff

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_dcbst(IR* ir, u32 opcode, JitContext ctx) {
    // TODO: do i really have to emulate this opcode? it sounds awful for performance.
    // for now i'll just do this silly hack...
    assert(opcode.bits(21, 25) == 0);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_divwx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    ir._if_no_phi(ir.get_reg(rb).equals(ir.constant(0)), () {
        IRVariable result = ir.get_reg(ra) >> 31;
        ir.set_reg(rd, result);

        if (oe) emit_set_xer_so_ov(ir, ir.constant(1));
        if (rc) emit_set_cr_flags_generic(ir, 0, result);
    }, () {
        IRVariable result   = ir.get_reg(ra) / ir.get_reg(rb);
        IRVariable overflow = ir.get_overflow();
        ir.set_reg(rd, result);

        if (oe) emit_set_xer_so_ov(ir, overflow);
        if (rc) emit_set_cr_flags_generic(ir, 0, result);
    });

    ir._if_no_phi(ir.get_reg(rb).equals(ir.constant(0xFFFF_FFFF)) & ir.get_reg(ra).equals(ir.constant(0x8000_0000)), () {
        ir.set_reg(rd, 0xFFFF_FFFF);

        if (oe) emit_set_xer_so_ov(ir, ir.constant(1));
        if (rc) emit_set_cr_flags_generic(ir, 0, ir.constant(0xFFFF_FFFF));
    });

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_divwux(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    ir._if_no_phi(ir.get_reg(rb).equals(ir.constant(0)), () {
        IRVariable result = ir.constant(0);
        ir.set_reg(rd, result);

        if (oe) emit_set_xer_so_ov(ir, ir.constant(1));
        if (rc) emit_set_cr_flags_generic(ir, 0, result);
    }, () {
        IRVariable result   = ir.get_reg(ra).unsigned_div(ir.get_reg(rb));
        IRVariable overflow = ir.get_overflow();
        ir.set_reg(rd, result);

        if (oe) emit_set_xer_so_ov(ir, overflow);
        if (rc) emit_set_cr_flags_generic(ir, 0, result);
    });

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_eqv(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) ^ ir.get_reg(rb));
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_extsb(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).sext(8);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_extsh(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).sext(16);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_hle(IR* ir, u32 opcode, JitContext ctx) {
    int hle_function_id = opcode.bits(21, 25);
    ir.run_hle_func(hle_function_id);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_icbi(IR* ir, u32 opcode, JitContext ctx) {
    // i'm just not going to emulate cache stuff

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_isync(IR* ir, u32 opcode, JitContext ctx) {
    // not needed for emulation

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_lbzu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    assert(ra != 0);
    assert(ra != rd);

    IRVariable address = ir.get_reg(ra) + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u8(address));
    ir.set_reg(ra, address);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_lfd(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    ir.set_reg(rd, ir.read_u64(ir.get_reg(ra) + sext_32(d, 16)).interpret_as_float());

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_lhz(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u16(address));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_lwz(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_lwzu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));
    ir.set_reg(ra, address);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_lwzx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + ir.get_reg(rb);
    ir.set_reg(rd, ir.read_u32(address));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mfmsr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(rd, ir.get_reg(GuestReg.MSR));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mtfsf(IR* ir, u32 opcode, JitContext ctx) {
    int fm = opcode.bits(17, 24);
    GuestReg frB = to_fpr(opcode.bits(11, 15));

    assert(opcode.bit(25) == 0);
    assert(opcode.bit(16) == 0);
    assert(opcode.bit(0) == 0);

    int mask = 0;
    for (int i = 0; i < 8; i++) {
        if (fm.bit(i)) {
            mask |= 0b1111 << (i * 4);
        }
    }

    ir.set_reg(GuestReg.FPSR, (ir.get_reg(GuestReg.FPSR) & ~mask) | (ir.get_reg(frB).to_int() & mask));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mfspr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);

    // assert(spr == 0b1000_00000);

    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(rd, ir.get_reg(src));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mftb(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int tb_id = opcode.bits(16, 20) | (opcode.bits(11, 15) << 5);

    GuestReg tb_reg;
    switch (tb_id) {
        case 268: tb_reg = GuestReg.TBL; break;
        case 269: tb_reg = GuestReg.TBU; break;
        default: assert(0);
    }

    ir.set_reg(rd, ir.get_reg(tb_reg));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mtmsr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(GuestReg.MSR, ir.get_reg(rs));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mtspr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);
    
    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(src, ir.get_reg(rd));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mulli(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd   = to_gpr(opcode.bits(21, 25));
    GuestReg ra   = to_gpr(opcode.bits(16, 20));
    int      simm = sext_32(opcode.bits(0, 15), 16);

    IRVariable result = ir.get_reg(ra) * simm;
    ir.set_reg(rd, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mullwx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    IRVariable result = ir.get_reg(ra) * ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mulhw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    // the broadway manual seems to indicate that this bit is 0,
    // but knowing this manual, i wouldn't be surprised if it can be
    // a 1. so i'll leave in the infrastructure for dealing with oe.
    assert(!oe);

    IRVariable result = ir.get_reg(ra).multiply_high_signed(ir.get_reg(rb));
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_mulhwu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    // the broadway manual seems to indicate that this bit is 0,
    // but knowing this manual, i wouldn't be surprised if it can be
    // a 1. so i'll leave in the infrastructure for dealing with oe.
    assert(!oe);

    IRVariable result = ir.get_reg(ra).multiply_high(ir.get_reg(rb));
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_nand(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) & ir.get_reg(rb));

    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_negx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    assert(opcode.bits(11, 15) == 0b00000);

    IRVariable result = ~ir.get_reg(ra) + 1;
    IRVariable overflow = ir.get_overflow();

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_nor(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) | ir.get_reg(rb));
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_or(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) | ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_orc(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) | ~ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_ori(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_oris(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15) << 16;

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_rlwimi(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      sh = opcode.bits(11, 15);
    int      mb = opcode.bits(6, 10);
    int      me = opcode.bits(1, 5);
    bool     rc = opcode.bit(0);

    int mask = generate_rlw_mask(mb, me);

    IRVariable result = ir.get_reg(rs);
    result = (result.rol(sh) & mask) | (ir.get_reg(ra) & ~mask);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_rlwinm(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      sh = opcode.bits(11, 15);
    int      mb = opcode.bits(6, 10);
    int      me = opcode.bits(1, 5);
    bool     rc = opcode.bit(0);

    int mask = generate_rlw_mask(mb, me);

    IRVariable result = ir.get_reg(rs);
    result = result.rol(sh) & mask;
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_rlwnm(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    int      mb = opcode.bits(6, 10);
    int      me = opcode.bits(1, 5);
    bool     rc = opcode.bit(0);

    int mask = generate_rlw_mask(mb, me);

    IRVariable result = ir.get_reg(rs);
    result = result.rol(ir.get_reg(rb) & 0x1F) & mask;
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_sc(IR* ir, u32 opcode, JitContext ctx) {
    // apparently syscalls are only used for "sync" and "isync" on the Wii
    // and that's something i don't need to emulate

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_slw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable shift = ir.get_reg(rb) & 0x3F;
    IRVariable result = ir.constant(0);

    ir._if(shift.lesser_unsigned(ir.constant(32)),
        () {
            result = ir.get_reg(rs) << shift;
        },
    );

    ir.set_reg(ra, result);
    IRVariable overflow = ir.get_overflow();

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_sraw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable operand = ir.get_reg(rs);
    IRVariable raw_shift = ir.get_reg(rb) & 0x3F;
    IRVariable shift = raw_shift;
    ir._if(shift.greater_unsigned(ir.constant(31)),
        () {
            shift = ir.constant(31);
        }
    );

    IRVariable result = operand >> shift;
    IRVariable carry = (result >> 31) & (operand.ctz().lesser_unsigned(raw_shift));

    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_srawi(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      sh = opcode.bits(11, 15);
    bool     rc = opcode.bit(0);

    IRVariable operand = ir.get_reg(rs);
    IRVariable result = operand >> sh;
    IRVariable carry = (result >> 31) & (operand.ctz().lesser_unsigned(ir.constant(sh)));

    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);


    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_srw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable shift = ir.get_reg(rb) & 0x3F;
    IRVariable operand = ir.get_reg(rs);
    ir._if(shift.greater_unsigned(ir.constant(31)),
        () {
            operand = ir.constant(0);
        }
    );

    IRVariable result = operand >>> shift;
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_stb(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u8(address, ir.get_reg(rs));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_stbu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.set_reg(ra, address);
    ir.write_u8(address, ir.get_reg(rs));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_sth(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    
    if (ra == 0) {
        ir.write_u16(ir.constant(sext_32(offset, 16)), ir.get_reg(rs));
    } else {
        ir.write_u16(ir.get_reg(ra) + sext_32(offset, 16), ir.get_reg(rs));
    }

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_stw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_stwx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0) == 0);

    IRVariable address = ra == 0 ? ir.constant(rb) : ir.get_reg(ra) + ir.constant(rb);
    ir.write_u32(address, ir.get_reg(rs));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_stwu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
    ir.set_reg(ra, address);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_subfx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    IRVariable operand = ~ir.get_reg(ra) + 1;
    IRVariable carry = ir.get_carry();
    IRVariable overflow = ir.get_overflow();
    IRVariable result = ir.get_reg(rb) + operand;
    IRVariable overflow2 = ir.get_overflow();
    carry = carry | ir.get_carry();
    overflow = overflow | overflow2;

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_subfcx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    IRVariable operand = ~ir.get_reg(ra) + 1;
    IRVariable carry = ir.get_carry();
    IRVariable overflow = ir.get_overflow();
    IRVariable result = ir.get_reg(rb) + operand;
    IRVariable overflow2 = ir.get_overflow();
    carry = carry | ir.get_carry();
    overflow = overflow | overflow2;
    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_subfex(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    IRVariable operand = (~ir.get_reg(ra) + emit_get_xer_ca(ir));
    IRVariable carry = ir.get_carry();
    IRVariable overflow = ir.get_overflow();
    IRVariable result = ir.get_reg(rb) + operand;
    IRVariable overflow2 = ir.get_overflow();
    carry = carry | ir.get_carry();
    overflow = overflow | overflow2;
    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_subfic(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    IRVariable result = (~ir.get_reg(ra)) + (sext_32(imm, 16) + 1);
    IRVariable carry = ir.get_carry();
    ir.set_reg(rd, result);

    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_subfmex(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));

    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result   = ~ir.get_reg(ra) + (emit_get_xer_ca(ir) - 1);
    IRVariable carry    = ir.get_carry();
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_subfzex(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    assert(opcode.bits(11, 15) == 0);
    IRVariable carry_in = emit_get_xer_ca(ir);

    IRVariable result = ~ir.get_reg(ra) + carry_in;
    IRVariable overflow = ir.get_overflow();
    IRVariable carry_out = ir.get_carry();

    ir.set_reg(rd, result);

    if (oe) emit_set_xer_so_ov(ir, overflow);
    if (rc) emit_set_cr_flags_generic(ir, 0, result);
    emit_set_xer_ca(ir, carry_out);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_sync(IR* ir, u32 opcode, JitContext ctx) {
    // not needed for emulation

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_xor(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    ir.set_reg(ra, ir.get_reg(rs) ^ ir.get_reg(rb));
    IRVariable overflow = ir.get_overflow();

    if (rc) emit_set_cr_flags_generic(ir, 0, ir.get_reg(ra));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_xori(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs  = to_gpr(opcode.bits(21, 25));
    GuestReg ra  = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    ir.set_reg(ra, ir.get_reg(rs) ^ imm);

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_xoris(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs  = to_gpr(opcode.bits(21, 25));
    GuestReg ra  = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    ir.set_reg(ra, ir.get_reg(rs) ^ (imm << 16));

    return GenerateRecipeAction.CONTINUE;
}

private GenerateRecipeAction emit_op_04(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp04SecondaryOpcode.PS_MR: return emit_ps_mr(ir, opcode, ctx);

        default: unimplemented_opcode(opcode, ctx); return GenerateRecipeAction.STOP;
    }
}

private GenerateRecipeAction emit_op_13(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp13SecondaryOpcode.BCCTR: return emit_bcctr(ir, opcode, ctx);
        case PrimaryOp13SecondaryOpcode.BCLR:  return emit_bclr (ir, opcode, ctx);
        case PrimaryOp13SecondaryOpcode.CRXOR: return emit_crxor(ir, opcode, ctx);
        case PrimaryOp13SecondaryOpcode.ISYNC: return emit_isync(ir, opcode, ctx);

        default: unimplemented_opcode(opcode, ctx); return GenerateRecipeAction.STOP;
    }
}

private GenerateRecipeAction emit_op_1F(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp1FSecondaryOpcode.ADD:     return emit_addx   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDC:    return emit_addcx  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDCO:   return emit_addcx  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDE:    return emit_addex  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDEO:   return emit_addex  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDO:    return emit_addx   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDME:   return emit_addmex (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDMEO:  return emit_addmex (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDZE:   return emit_addzex (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ADDZEO:  return emit_addzex (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.AND:     return emit_and    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ANDC:    return emit_andc   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.CNTLZW:  return emit_cntlzw (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.CMP:     return emit_cmp    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.CMPL:    return emit_cmpl   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DCBF:    return emit_dcbf   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DCBI:    return emit_dcbi   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DCBST:   return emit_dcbst  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DIVW:    return emit_divwx  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DIVWO:   return emit_divwx  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DIVWU:   return emit_divwux (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.DIVWUO:  return emit_divwux (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.EQV:     return emit_eqv    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.EXTSB:   return emit_extsb  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.EXTSH:   return emit_extsh  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.HLE:     return emit_hle    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ICBI:    return emit_icbi   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.LWZX:    return emit_lwzx   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MFMSR:   return emit_mfmsr  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MFSPR:   return emit_mfspr  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MFTB:    return emit_mftb   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MTMSR:   return emit_mtmsr  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MTSPR:   return emit_mtspr  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MULLW:   return emit_mullwx (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MULLWO:  return emit_mullwx (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MULHW:   return emit_mulhw  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.MULHWU:  return emit_mulhwu (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.NAND:    return emit_nand   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.NEG:     return emit_negx   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.NEGO:    return emit_negx   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.NOR:     return emit_nor    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.OR:      return emit_or     (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.ORC:     return emit_orc    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SLW:     return emit_slw    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SRAW:    return emit_sraw   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SRAWI:   return emit_srawi  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SRW:     return emit_srw    (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.STWX:    return emit_stwx   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBF:    return emit_subfx  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFO:   return emit_subfx  (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFC:   return emit_subfcx (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFCO:  return emit_subfcx (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFE:   return emit_subfex (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFEO:  return emit_subfex (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFME:  return emit_subfmex(ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFMEO: return emit_subfmex(ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFZE:  return emit_subfzex(ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SUBFZEO: return emit_subfzex(ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.SYNC:    return emit_sync   (ir, opcode, ctx);
        case PrimaryOp1FSecondaryOpcode.XOR:     return emit_xor    (ir, opcode, ctx);

        default: unimplemented_opcode(opcode, ctx); return GenerateRecipeAction.STOP;
    }
}

private GenerateRecipeAction emit_op_3B(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        case PrimaryOp3BSecondaryOpcode.FADDSX:   return emit_faddsx  (ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FDIVSX:   return emit_fdivsx  (ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FMADDSX:  return emit_fmaddsx (ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FMSUBSX:  return emit_fmsubsx (ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FMULSX:   return emit_fmulsx  (ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FNMADDSX: return emit_fnmaddsx(ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FNMSUBSX: return emit_fnmsubsx(ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FRESX:    return emit_fresx   (ir, opcode, ctx);
        case PrimaryOp3BSecondaryOpcode.FSUBSX:   return emit_fsubsx  (ir, opcode, ctx);

        default: unimplemented_opcode(opcode, ctx); return GenerateRecipeAction.STOP;
    }
}

private GenerateRecipeAction emit_op_3F(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp3FSecondaryOpcode.FABSX:  return emit_fabsx  (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FCTIWX: return emit_fctiwx (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FMR:    return emit_fmr    (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FNABSX: return emit_fnabsx (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FNEGX:  return emit_fnegx  (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.MFTSB1: return emit_mftsb1 (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.MTFSF:  return emit_mtfsf  (ir, opcode, ctx);
        default: break;
    }

    secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        case PrimaryOp3FSecondaryOpcode.FADDX:   return emit_faddx  (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FDIVX:   return emit_fdivx  (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FMADDX:  return emit_fmaddx (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FMSUBX:  return emit_fmsubx (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FMULX:   return emit_fmulx  (ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FNMADDX: return emit_fnmaddx(ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FNMSUBX: return emit_fnmsubx(ir, opcode, ctx);
        case PrimaryOp3FSecondaryOpcode.FSEL:    return emit_fsel   (ir, opcode, ctx);
        default: unimplemented_opcode(opcode, ctx); return GenerateRecipeAction.STOP;
    }
}

public GenerateRecipeAction disassemble(IR* ir, u32 opcode, JitContext ctx) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:   return emit_addi  (ir, opcode, ctx);
        case PrimaryOpcode.ADDIC:  return emit_addic (ir, opcode, ctx);
        case PrimaryOpcode.ADDIC_: return emit_addic_(ir, opcode, ctx);
        case PrimaryOpcode.ADDIS:  return emit_addis (ir, opcode, ctx);
        case PrimaryOpcode.ANDI:   return emit_andi  (ir, opcode, ctx);
        case PrimaryOpcode.ANDIS:  return emit_andis (ir, opcode, ctx);
        case PrimaryOpcode.B:      return emit_b     (ir, opcode, ctx);
        case PrimaryOpcode.BC:     return emit_bc    (ir, opcode, ctx);
        case PrimaryOpcode.CMPLI:  return emit_cmpli (ir, opcode, ctx);
        case PrimaryOpcode.CMPI:   return emit_cmpi  (ir, opcode, ctx);
        case PrimaryOpcode.LBZU:   return emit_lbzu  (ir, opcode, ctx);
        case PrimaryOpcode.LFD:    return emit_lfd   (ir, opcode, ctx);
        case PrimaryOpcode.LHZ:    return emit_lhz   (ir, opcode, ctx);
        case PrimaryOpcode.LWZ:    return emit_lwz   (ir, opcode, ctx);
        case PrimaryOpcode.LWZU:   return emit_lwzu  (ir, opcode, ctx);
        case PrimaryOpcode.MULLI:  return emit_mulli (ir, opcode, ctx);
        case PrimaryOpcode.ORI:    return emit_ori   (ir, opcode, ctx);
        case PrimaryOpcode.ORIS:   return emit_oris  (ir, opcode, ctx);
        case PrimaryOpcode.PSQ_L:  return emit_psq_l (ir, opcode, ctx);
        case PrimaryOpcode.RLWIMI: return emit_rlwimi(ir, opcode, ctx);
        case PrimaryOpcode.RLWINM: return emit_rlwinm(ir, opcode, ctx);
        case PrimaryOpcode.RLWNM:  return emit_rlwnm (ir, opcode, ctx);
        case PrimaryOpcode.SC:     return emit_sc    (ir, opcode, ctx);
        case PrimaryOpcode.STB:    return emit_stb   (ir, opcode, ctx);
        case PrimaryOpcode.STBU:   return emit_stbu  (ir, opcode, ctx);
        case PrimaryOpcode.STH:    return emit_sth   (ir, opcode, ctx);
        case PrimaryOpcode.STW:    return emit_stw   (ir, opcode, ctx);
        case PrimaryOpcode.STWU:   return emit_stwu  (ir, opcode, ctx);
        case PrimaryOpcode.SUBFIC: return emit_subfic(ir, opcode, ctx);
        case PrimaryOpcode.XORI:   return emit_xori  (ir, opcode, ctx);
        case PrimaryOpcode.XORIS:  return emit_xoris (ir, opcode, ctx);

        case PrimaryOpcode.OP_04:  return emit_op_04 (ir, opcode, ctx);
        case PrimaryOpcode.OP_13:  return emit_op_13 (ir, opcode, ctx);
        case PrimaryOpcode.OP_1F:  return emit_op_1F (ir, opcode, ctx);
        case PrimaryOpcode.OP_3B:  return emit_op_3B (ir, opcode, ctx);
        case PrimaryOpcode.OP_3F:  return emit_op_3F (ir, opcode, ctx);

        default: unimplemented_opcode(opcode, ctx); return GenerateRecipeAction.STOP;
    }
}

public size_t generate_recipe(IR* ir, Mem mem, JitContext ctx, u32 address) {
    size_t num_opcodes_processed = 0;
    
    while (num_opcodes_processed < MAX_GUEST_OPCODES_PER_RECIPE) {
        GenerateRecipeAction action = disassemble(ir, mem.read_be_u32(address), ctx);
        ctx.pc += 4;
        address += 4;
        num_opcodes_processed++;
        
        if (action == GenerateRecipeAction.STOP) {
            break;
        }

        if (num_opcodes_processed == MAX_GUEST_OPCODES_PER_RECIPE) {
            ir.set_reg(GuestReg.PC, ctx.pc);
        }
    }

    return num_opcodes_processed;
}

private void unimplemented_opcode(u32 opcode, JitContext ctx) {
    import capstone;

    auto cs = create(Arch.ppc, ModeFlags(Mode.bit32));
    auto res = cs.disasm((cast(ubyte*) &opcode)[0 .. 4], ctx.pc);
    foreach (instr; res) {
        log_jit("0x%08x | %s\t\t%s", ctx.pc, instr.mnemonic, instr.opStr);
    }

    error_jit("Unimplemented opcode: 0x%08x (at PC 0x%08x) (Primary: %x, Secondary: %x)", opcode, ctx.pc, opcode.bits(26, 31), opcode.bits(1, 10));
}