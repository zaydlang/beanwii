module emu.hw.broadway.jit.emission.emit;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.flags;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.opcode;
import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.log;
import util.number;
import xbyak;

enum MAX_GUEST_OPCODES_PER_RECIPE = 1;

enum EmissionAction {
    STOP,
    CONTINUE,
}

private EmissionAction emit_addcx(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto rd       = code.get_reg(guest_rd);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    code.mov(rd, ra);
    code.add(rd, rb);
    code.set_reg(guest_rd, rd);
    
    set_flags(code, rc, oe, ra, rb, rd);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addex(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_addi(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm = sext_32(opcode.bits(0, 15), 16);

    if (ra == 0) {
        ir.set_reg(rd, simm);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + simm);
    }

    return EmissionAction.CONTINUE;
*/

    GuestReg rd_guest = opcode.bits(21, 25).to_gpr;
    GuestReg ra_guest = opcode.bits(16, 20).to_gpr;
    int simm = sext_32(opcode.bits(0, 15), 16);

    if (ra_guest == GuestReg.R0) {
        code.set_reg(rd_guest, simm);
    } else {
        auto ra = code.get_reg(ra_guest);
        code.add(ra, simm);
        code.set_reg(rd_guest, ra);
    }

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addic(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_addic_(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_addis(Code code, u32 opcode) {
    GuestReg rd_guest = opcode.bits(21, 25).to_gpr;
    GuestReg ra_guest = opcode.bits(16, 20).to_gpr;
    int simm = opcode.bits(0, 15);

    if (ra_guest == GuestReg.R0) {
        code.set_reg(rd_guest, simm << 16);
    } else {
        auto ra = code.get_reg(ra_guest);
        code.lea(ra, dword [ra + (simm << 16)]);
        code.set_reg(rd_guest, ra);
    }

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addmex(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_addx(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_addzex(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_and(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) & ir.get_reg(rb);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_andc(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) & ~ir.get_reg(rb);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_andi(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) & uimm;
    ir.set_reg(ra, result);

    emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_andis(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) & (uimm << 16);
    ir.set_reg(ra, result);

    emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.STOP;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_b(Code code, u32 opcode) {/*
    bool aa = opcode.bit(1);
    bool lk = opcode.bit(0);
    int  li = opcode.bits(2, 25);

    u32 branch_address = sext_32(li, 24) << 2;
    if (!aa) branch_address += ctx.pc;

    if (lk) ir.set_reg(GuestReg.LR, ctx.pc + 4);

    // if (branch_address == ctx.pc) error_broadway("branch to self");

    ir.set_reg(GuestReg.PC, branch_address);

    return EmissionAction.STOP;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_bc(Code code, u32 opcode) {/*
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

    return EmissionAction.STOP;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_bcctr(Code code, u32 opcode) {/*
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

    return EmissionAction.STOP;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_bclr(Code code, u32 opcode) {/*
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    if (lk) {
        ir.branch_with_link(cond_ok, ctx.pc + 4, ir.get_reg(GuestReg.LR), ir.constant(ctx.pc) + 4);
    } else {
        ir.branch(cond_ok, ir.get_reg(GuestReg.LR), ir.constant(ctx.pc) + 4);
    }

    return EmissionAction.STOP;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_cntlzw(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).clz();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_cmp(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_cmpl(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_cmpli(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_cmpi(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_crxor(Code code, u32 opcode) {/*
    int crbD = 31 - opcode.bits(21, 25);
    int crbA = 31 - opcode.bits(16, 20);
    int crbB = 31 - opcode.bits(11, 15);

    assert(opcode.bit(0) == 0);

    IRVariable cr = ir.get_reg(GuestReg.CR);
    cr = cr & ~(1 << crbD);
    cr = cr | ((((cr >> crbA) & 1) ^ ((cr >> crbB) & 1)) << crbD);
    ir.set_reg(GuestReg.CR, cr);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_dcbf(Code code, u32 opcode) {/*
    // i'm just not going to emulate cache stuff

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_dcbi(Code code, u32 opcode) {/*
    // i'm just not going to emulate cache stuff

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_dcbst(Code code, u32 opcode) {/*
    // TODO: do i really have to emulate this opcode? it sounds awful for performance.
    // for now i'll just do this silly hack...
    assert(opcode.bits(21, 25) == 0);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_divwx(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_divwux(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_eqv(Code code, u32 opcode) {/*
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) ^ ir.get_reg(rb));
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_extsb(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).sext(8);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_extsh(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).sext(16);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_hle(Code code, u32 opcode) {/*
    int hle_function_id = opcode.bits(21, 25);
    ir.run_hle_func(hle_function_id);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_icbi(Code code, u32 opcode) {/*
    // i'm just not going to emulate cache stuff

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_isync(Code code, u32 opcode) {/*
    // not needed for emulation

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_lbzu(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    assert(ra != 0);
    assert(ra != rd);

    IRVariable address = ir.get_reg(ra) + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u8(address));
    ir.set_reg(ra, address);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_lfd(Code code, u32 opcode) {/*
    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    ir.set_reg(rd, ir.read_u64(ir.get_reg(ra) + sext_32(d, 16)).interpret_as_float());

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_lhz(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u16(address));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_lwz(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_lwzu(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));
    ir.set_reg(ra, address);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_lwzx(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + ir.get_reg(rb);
    ir.set_reg(rd, ir.read_u32(address));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mfmsr(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(rd, ir.get_reg(GuestReg.MSR));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mtfsf(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mfspr(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);

    // assert(spr == 0b1000_00000);

    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(rd, ir.get_reg(src));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mftb(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int tb_id = opcode.bits(16, 20) | (opcode.bits(11, 15) << 5);

    GuestReg tb_reg;
    switch (tb_id) {
        case 268: tb_reg = GuestReg.TBL; break;
        case 269: tb_reg = GuestReg.TBU; break;
        default: assert(0);
    }

    ir.set_reg(rd, ir.get_reg(tb_reg));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mtmsr(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(GuestReg.MSR, ir.get_reg(rs));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mtspr(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);
    
    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(src, ir.get_reg(rd));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mulli(Code code, u32 opcode) {/*
    GuestReg rd   = to_gpr(opcode.bits(21, 25));
    GuestReg ra   = to_gpr(opcode.bits(16, 20));
    int      simm = sext_32(opcode.bits(0, 15), 16);

    IRVariable result = ir.get_reg(ra) * simm;
    ir.set_reg(rd, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mullwx(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mulhw(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_mulhwu(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_nand(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) & ir.get_reg(rb));

    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_negx(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_nor(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) | ir.get_reg(rb));
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_or(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) | ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_orc(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) | ~ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_ori(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_oris(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15) << 16;

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_rlwimi(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_rlwinm(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_rlwnm(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_sc(Code code, u32 opcode) {/*
    // apparently syscalls are only used for "sync" and "isync" on the Wii
    // and that's something i don't need to emulate

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_slw(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_sraw(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_srawi(Code code, u32 opcode) {/*
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


    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_srw(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_stb(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u8(address, ir.get_reg(rs));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_stbu(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.set_reg(ra, address);
    ir.write_u8(address, ir.get_reg(rs));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_sth(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    
    if (ra == 0) {
        ir.write_u16(ir.constant(sext_32(offset, 16)), ir.get_reg(rs));
    } else {
        ir.write_u16(ir.get_reg(ra) + sext_32(offset, 16), ir.get_reg(rs));
    }

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_stw(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_stwx(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0) == 0);

    IRVariable address = ra == 0 ? ir.constant(rb) : ir.get_reg(ra) + ir.constant(rb);
    ir.write_u32(address, ir.get_reg(rs));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_stwu(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
    ir.set_reg(ra, address);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_subfx(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_subfcx(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_subfex(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_subfic(Code code, u32 opcode) {/*
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    IRVariable result = (~ir.get_reg(ra)) + (sext_32(imm, 16) + 1);
    IRVariable carry = ir.get_carry();
    ir.set_reg(rd, result);

    emit_set_xer_ca(ir, carry);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_subfmex(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_subfzex(Code code, u32 opcode) {/*
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

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_sync(Code code, u32 opcode) {/*
    // not needed for emulation

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_xor(Code code, u32 opcode) {/*
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    ir.set_reg(ra, ir.get_reg(rs) ^ ir.get_reg(rb));
    IRVariable overflow = ir.get_overflow();

    if (rc) generate_recipeemit_set_cr_flags_generic(ir, 0, ir.get_reg(ra));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_xori(Code code, u32 opcode) {/*
    GuestReg rs  = to_gpr(opcode.bits(21, 25));
    GuestReg ra  = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    ir.set_reg(ra, ir.get_reg(rs) ^ imm);

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_xoris(Code code, u32 opcode) {/*
    GuestReg rs  = to_gpr(opcode.bits(21, 25));
    GuestReg ra  = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    ir.set_reg(ra, ir.get_reg(rs) ^ (imm << 16));

    return EmissionAction.CONTINUE;
*/
return EmissionAction.STOP;
}

private EmissionAction emit_op_04(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        // case PrimaryOp04SecondaryOpcode.PS_MR: return emit_ps_mr(ir, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_13(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        // case PrimaryOp13SecondaryOpcode.BCCTR: return emit_bcctr(ir, opcode);
        // case PrimaryOp13SecondaryOpcode.BCLR:  return emit_bclr (ir, opcode);
        // case PrimaryOp13SecondaryOpcode.CRXOR: return emit_crxor(ir, opcode);
        // case PrimaryOp13SecondaryOpcode.ISYNC: return emit_isync(ir, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_1F(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        // case PrimaryOp1FSecondaryOpcode.ADD:     return emit_addx   (ir, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDC:    return emit_addcx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDCO:   return emit_addcx  (code, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDE:    return emit_addex  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDEO:   return emit_addex  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDO:    return emit_addx   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDME:   return emit_addmex (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDMEO:  return emit_addmex (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDZE:   return emit_addzex (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ADDZEO:  return emit_addzex (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.AND:     return emit_and    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ANDC:    return emit_andc   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.CNTLZW:  return emit_cntlzw (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.CMP:     return emit_cmp    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.CMPL:    return emit_cmpl   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DCBF:    return emit_dcbf   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DCBI:    return emit_dcbi   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DCBST:   return emit_dcbst  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DIVW:    return emit_divwx  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DIVWO:   return emit_divwx  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DIVWU:   return emit_divwux (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.DIVWUO:  return emit_divwux (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.EQV:     return emit_eqv    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.EXTSB:   return emit_extsb  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.EXTSH:   return emit_extsh  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.HLE:     return emit_hle    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ICBI:    return emit_icbi   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.LWZX:    return emit_lwzx   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MFMSR:   return emit_mfmsr  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MFSPR:   return emit_mfspr  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MFTB:    return emit_mftb   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MTMSR:   return emit_mtmsr  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MTSPR:   return emit_mtspr  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MULLW:   return emit_mullwx (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MULLWO:  return emit_mullwx (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MULHW:   return emit_mulhw  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.MULHWU:  return emit_mulhwu (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.NAND:    return emit_nand   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.NEG:     return emit_negx   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.NEGO:    return emit_negx   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.NOR:     return emit_nor    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.OR:      return emit_or     (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.ORC:     return emit_orc    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SLW:     return emit_slw    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SRAW:    return emit_sraw   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SRAWI:   return emit_srawi  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SRW:     return emit_srw    (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.STWX:    return emit_stwx   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBF:    return emit_subfx  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFO:   return emit_subfx  (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFC:   return emit_subfcx (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFCO:  return emit_subfcx (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFE:   return emit_subfex (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFEO:  return emit_subfex (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFME:  return emit_subfmex(ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFMEO: return emit_subfmex(ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFZE:  return emit_subfzex(ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SUBFZEO: return emit_subfzex(ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.SYNC:    return emit_sync   (ir, opcode);
        // case PrimaryOp1FSecondaryOpcode.XOR:     return emit_xor    (ir, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_3B(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        // case PrimaryOp3BSecondaryOpcode.FADDSX:   return emit_faddsx  (ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FDIVSX:   return emit_fdivsx  (ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FMADDSX:  return emit_fmaddsx (ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FMSUBSX:  return emit_fmsubsx (ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FMULSX:   return emit_fmulsx  (ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FNMADDSX: return emit_fnmaddsx(ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FNMSUBSX: return emit_fnmsubsx(ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FRESX:    return emit_fresx   (ir, opcode);
        // case PrimaryOp3BSecondaryOpcode.FSUBSX:   return emit_fsubsx  (ir, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_3F(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        // case PrimaryOp3FSecondaryOpcode.FABSX:  return emit_fabsx  (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FCTIWX: return emit_fctiwx (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMR:    return emit_fmr    (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNABSX: return emit_fnabsx (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNEGX:  return emit_fnegx  (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.MFTSB1: return emit_mftsb1 (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.MTFSF:  return emit_mtfsf  (ir, opcode);
        default: break;
    }

    secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        // case PrimaryOp3FSecondaryOpcode.FADDX:   return emit_faddx  (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FDIVX:   return emit_fdivx  (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMADDX:  return emit_fmaddx (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMSUBX:  return emit_fmsubx (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMULX:   return emit_fmulx  (ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNMADDX: return emit_fnmaddx(ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNMSUBX: return emit_fnmsubx(ir, opcode);
        // case PrimaryOp3FSecondaryOpcode.FSEL:    return emit_fsel   (ir, opcode);
        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

public EmissionAction disassemble(Code code, u32 opcode) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:   return emit_addi  (code, opcode);
        // case PrimaryOpcode.ADDIC:  return emit_addic (ir, opcode);
        // case PrimaryOpcode.ADDIC_: return emit_addic_(ir, opcode);
        case PrimaryOpcode.ADDIS:  return emit_addis (code, opcode);
        // case PrimaryOpcode.ANDI:   return emit_andi  (ir, opcode);
        // case PrimaryOpcode.ANDIS:  return emit_andis (ir, opcode);
        // case PrimaryOpcode.B:      return emit_b     (ir, opcode);
        // case PrimaryOpcode.BC:     return emit_bc    (ir, opcode);
        // case PrimaryOpcode.CMPLI:  return emit_cmpli (ir, opcode);
        // case PrimaryOpcode.CMPI:   return emit_cmpi  (ir, opcode);
        // case PrimaryOpcode.LBZU:   return emit_lbzu  (ir, opcode);
        // case PrimaryOpcode.LFD:    return emit_lfd   (ir, opcode);
        // case PrimaryOpcode.LHZ:    return emit_lhz   (ir, opcode);
        // case PrimaryOpcode.LWZ:    return emit_lwz   (ir, opcode);
        // case PrimaryOpcode.LWZU:   return emit_lwzu  (ir, opcode);
        // case PrimaryOpcode.MULLI:  return emit_mulli (ir, opcode);
        // case PrimaryOpcode.ORI:    return emit_ori   (ir, opcode);
        // case PrimaryOpcode.ORIS:   return emit_oris  (ir, opcode);
        // case PrimaryOpcode.PSQ_L:  return emit_psq_l (ir, opcode);
        // case PrimaryOpcode.RLWIMI: return emit_rlwimi(ir, opcode);
        // case PrimaryOpcode.RLWINM: return emit_rlwinm(ir, opcode);
        // case PrimaryOpcode.RLWNM:  return emit_rlwnm (ir, opcode);
        // case PrimaryOpcode.SC:     return emit_sc    (ir, opcode);
        // case PrimaryOpcode.STB:    return emit_stb   (ir, opcode);
        // case PrimaryOpcode.STBU:   return emit_stbu  (ir, opcode);
        // case PrimaryOpcode.STH:    return emit_sth   (ir, opcode);
        // case PrimaryOpcode.STW:    return emit_stw   (ir, opcode);
        // case PrimaryOpcode.STWU:   return emit_stwu  (ir, opcode);
        // case PrimaryOpcode.SUBFIC: return emit_subfic(ir, opcode);
        // case PrimaryOpcode.XORI:   return emit_xori  (ir, opcode);
        // case PrimaryOpcode.XORIS:  return emit_xoris (ir, opcode);

        case PrimaryOpcode.OP_04:  return emit_op_04 (code, opcode);
        case PrimaryOpcode.OP_13:  return emit_op_13 (code, opcode);
        case PrimaryOpcode.OP_1F:  return emit_op_1F (code, opcode);
        case PrimaryOpcode.OP_3B:  return emit_op_3B (code, opcode);
        case PrimaryOpcode.OP_3F:  return emit_op_3F (code, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

public size_t emit(Code code, Mem mem, u32 address) {
    size_t num_opcodes_processed = 0;
    
    // while (num_opcodes_processed < MAX_GUEST_OPCODES_PER_RECIPE) {
        EmissionAction action = disassemble(code, mem.read_be_u32(address));
        // ctx.pc += 4;
        // address += 4;
        // num_opcodes_processed++;
        
        // if (action == EmissionAction.STOP) {
            // break;
        // }

        // if (num_opcodes_processed == MAX_GUEST_OPCODES_PER_RECIPE) {
            // ir.set_reg(GuestReg.PC, ctx.pc);
        // }
    // }

    return 1;
}

private void unimplemented_opcode(u32 opcode) {
    import capstone;

    auto cs = create(Arch.ppc, ModeFlags(Mode.bit32));
    auto res = cs.disasm((cast(ubyte*) &opcode)[0 .. 4], 0);
    foreach (instr; res) {
        log_jit("0x%08x | %s\t\t%s", 0, instr.mnemonic, instr.opStr);
    }

    error_jit("Unimplemented opcode: 0x%08x (at PC 0x%08x) (Primary: %x, Secondary: %x)", opcode, 0, opcode.bits(26, 31), opcode.bits(1, 10));
}
