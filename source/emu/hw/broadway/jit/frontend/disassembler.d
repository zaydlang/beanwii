module emu.hw.broadway.jit.frontend.disassembler;

import emu.hw.broadway.jit.frontend.floating_point;
import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.frontend.helpers;
import emu.hw.broadway.jit.frontend.opcode;
import emu.hw.broadway.jit.frontend.paired_single;
import emu.hw.broadway.jit.ir.ir;
import emu.hw.broadway.jit.jit;
import util.bitop;
import util.log;
import util.number;

private void emit_addcx(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_addex(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_addi(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm = sext_32(opcode.bits(0, 15), 16);

    if (ra == 0) {
        ir.set_reg(rd, simm);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + simm);
    }
}

private void emit_addic(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_addic_(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_addis(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm = opcode.bits(0, 15); // no need to sext cuz it gets shifted by 16

    if (ra == 0) {
        ir.set_reg(rd, simm << 16);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + (simm << 16));
    }
}

private void emit_addmex(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_addx(IR* ir, u32 opcode, JitContext ctx) {
    // 7dcdbe15
    // 011111 01110 01101 10111 110 0001 0101
    //        14    13    23
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
}

private void emit_addzex(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_and(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) & ir.get_reg(rb);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_andc(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) & ~ir.get_reg(rb);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_andi(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) & uimm;
    ir.set_reg(ra, result);

    emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_andis(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) & (uimm << 16);
    ir.set_reg(ra, result);

    emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_b(IR* ir, u32 opcode, JitContext ctx) {
    bool aa = opcode.bit(1);
    bool lk = opcode.bit(0);
    int  li = opcode.bits(2, 25);

    u32 branch_address = sext_32(li, 24) << 2;
    if (!aa) branch_address += ctx.pc;

    if (lk) ir.set_reg(GuestReg.LR, ctx.pc + 4);

    if (branch_address == ctx.pc) error_broadway("branch to self");

    ir.set_reg(GuestReg.PC, branch_address);
}

private void emit_bc(IR* ir, u32 opcode, JitContext ctx) {
    bool lk = opcode.bit(0);
    bool aa = opcode.bit(1);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);
    int  bd = opcode.bits(2, 15);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi);

    if (lk) ir.set_reg(GuestReg.LR, ctx.pc + 4);

    ir._if(cond_ok, () {
        if (lk) {
            ir.set_reg(GuestReg.LR, ctx.pc + 4);
        }

        if (aa) {
            ir.set_reg(GuestReg.PC, ir.constant(sext_32(bd, 14) << 2));
        } else {
            ir.set_reg(GuestReg.PC, ctx.pc + (sext_32(bd, 14) << 2));
        }
    });
}

private void emit_bcctr(IR* ir, u32 opcode, JitContext ctx) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    assert(opcode.bits(11, 15) == 0);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    ir._if(cond_ok, () { 
        if (lk) ir.set_reg(GuestReg.LR, ctx.pc + 4);

        // TODO: insert an assert into the JIT'ted code that checks that LR is never un-aligned
        ir.set_reg(GuestReg.PC, ir.get_reg(GuestReg.CTR));
    });
}

private void emit_bclr(IR* ir, u32 opcode, JitContext ctx) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    ir._if(cond_ok, () { 
        if (lk) ir.set_reg(GuestReg.LR, ctx.pc + 4);

        // TODO: insert an assert into the JIT'ted code that checks that LR is never un-aligned
        ir.set_reg(GuestReg.PC, ir.get_reg(GuestReg.LR));
    });
}

private void emit_cntlzw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool     rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).clz();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_cmp(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_cmpl(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_cmpli(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_cmpi(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_crxor(IR* ir, u32 opcode, JitContext ctx) {
    int crbD = 31 - opcode.bits(21, 25);
    int crbA = 31 - opcode.bits(16, 20);
    int crbB = 31 - opcode.bits(11, 15);

    assert(opcode.bit(0) == 0);

    IRVariable cr = ir.get_reg(GuestReg.CR);
    cr = cr & ~(1 << crbD);
    cr = cr | ((((cr >> crbA) & 1) ^ ((cr >> crbB) & 1)) << crbD);
    ir.set_reg(GuestReg.CR, cr);
}

private void emit_dcbf(IR* ir, u32 opcode, JitContext ctx) {
    // i'm just not going to emulate cache stuff
}

private void emit_dcbi(IR* ir, u32 opcode, JitContext ctx) {
    // i'm just not going to emulate cache stuff
}

private void emit_dcbst(IR* ir, u32 opcode, JitContext ctx) {
    // TODO: do i really have to emulate this opcode? it sounds awful for performance.
    // for now i'll just do this silly hack...
    assert(opcode.bits(21, 25) == 0);
}

private void emit_divwx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);
    bool     oe = opcode.bit(10);

    import emu.hw.broadway.jit.backend.x86_64.emitter;
    // 7ebc0fd6
    // 011111 10101 11100 00001 111 1101 0110

    // 7d99bfd7
    // 011111 01100 11001 10111 111
 
// LOG: PC: 0x80004200 CR: 0x55090080 FPSCR: 0x00000000 XER: 0x80000000 MSR: 0x00002032 LR: 0x00000000 
// LOG: fbe0dd63 ffff8065 fb74327a 13fecf5f 0456d060 db8ca980 ba5646de 0000000e 
// LOG: a2a2d9e5 00003070 ffffffff 442294d8 00000000 8998ffff 1b788065 00003172 
// LOG: 57aa714e fffff948 ffffffff ffffd9e5 02800000 00000000 af9f4ce7 8d20fe59 
// LOG: 00000061 57aa79ef 00000060 a80b2466 00000000 0c30f6a2 32a6cb6e ff712860
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
}

private void emit_divwux(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_eqv(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) ^ ir.get_reg(rb));
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_extsb(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).sext(8);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_extsh(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 15) == 0);

    IRVariable result = ir.get_reg(rs).sext(16);
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_hle(IR* ir, u32 opcode, JitContext ctx) {
    int hle_function_id = opcode.bits(21, 25);
    ir.run_hle_func(hle_function_id);
}

private void emit_icbi(IR* ir, u32 opcode, JitContext ctx) {
    // i'm just not going to emulate cache stuff
}

private void emit_isync(IR* ir, u32 opcode, JitContext ctx) {
    // not needed for emulation
}

private void emit_lbzu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    assert(ra != 0);
    assert(ra != rd);

    IRVariable address = ir.get_reg(ra) + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u8(address));
    ir.set_reg(ra, address);
}

private void emit_lfd(IR* ir, u32 opcode, JitContext ctx) {
    import emu.hw.broadway.jit.backend.x86_64.emitter;

    GuestReg rd = to_fpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    ir.set_reg(rd, ir.read_u64(ir.get_reg(ra) + sext_32(d, 16)).interpret_as_float());
}

private void emit_lhz(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u16(address));
}

private void emit_lwz(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));
}

private void emit_lwzu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));
    ir.set_reg(ra, address);
}

private void emit_lwzx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + ir.get_reg(rb);
    ir.set_reg(rd, ir.read_u32(address));
}

private void emit_mfmsr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(rd, ir.get_reg(GuestReg.MSR));
}

private void emit_mtfsf(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_mfspr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);

    // assert(spr == 0b1000_00000);

    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(rd, ir.get_reg(src));
}

private void emit_mftb(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int tb_id = opcode.bits(16, 20) || (opcode.bits(11, 15) << 5);

    GuestReg tb_reg;
    switch (tb_id) {
        case 268: tb_reg = GuestReg.TBL; break;
        case 269: tb_reg = GuestReg.TBU; break;
        default: assert(0);
    }

    ir.set_reg(rd, ir.get_reg(tb_reg));
}

private void emit_mtmsr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(GuestReg.MSR, ir.get_reg(rs));
}

private void emit_mtspr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);
    
    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(src, ir.get_reg(rd));
}

private void emit_mulli(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd   = to_gpr(opcode.bits(21, 25));
    GuestReg ra   = to_gpr(opcode.bits(16, 20));
    int      simm = sext_32(opcode.bits(0, 15), 16);

    IRVariable result = ir.get_reg(ra) * simm;
    ir.set_reg(rd, result);
}

private void emit_mullwx(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_mulhw(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_mulhwu(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_nand(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) & ir.get_reg(rb));

    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_negx(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_nor(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ~(ir.get_reg(rs) | ir.get_reg(rb));
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_or(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) | ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_orc(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    IRVariable result = ir.get_reg(rs) | ~ir.get_reg(rb);
    IRVariable overflow = ir.get_overflow();
    ir.set_reg(ra, result);

    if (rc) emit_set_cr_flags_generic(ir, 0, result);
}

private void emit_ori(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);
}

private void emit_oris(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15) << 16;

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);
}

private void emit_rlwimi(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_rlwinm(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_rlwnm(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_sc(IR* ir, u32 opcode, JitContext ctx) {
    // apparently syscalls are only used for "sync" and "isync" on the Wii
    // and that's something i don't need to emulate
}

private void emit_slw(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_sraw(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_srawi(IR* ir, u32 opcode, JitContext ctx) {
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

}

private void emit_srw(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_stb(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u8(address, ir.get_reg(rs));
}

private void emit_stbu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.set_reg(ra, address);
    ir.write_u8(address, ir.get_reg(rs));
}

private void emit_sth(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    
    if (ra == 0) {
        ir.write_u16(ir.constant(sext_32(offset, 16)), ir.get_reg(rs));
    } else {
        ir.write_u16(ir.get_reg(ra) + sext_32(offset, 16), ir.get_reg(rs));
    }
}

private void emit_stw(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
}

private void emit_stwx(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0) == 0);

    IRVariable address = ra == 0 ? ir.constant(rb) : ir.get_reg(ra) + ir.constant(rb);
    ir.write_u32(address, ir.get_reg(rs));
}

private void emit_stwu(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
    ir.set_reg(ra, address);
}

private void emit_subfx(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_subfcx(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_subfex(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_subfic(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    IRVariable result = (~ir.get_reg(ra)) + (sext_32(imm, 16) + 1);
    IRVariable carry = ir.get_carry();
    ir.set_reg(rd, result);

    emit_set_xer_ca(ir, carry);
}

private void emit_subfmex(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_subfzex(IR* ir, u32 opcode, JitContext ctx) {
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
}

private void emit_sync(IR* ir, u32 opcode, JitContext ctx) {
    // not needed for emulation
}

private void emit_xor(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    ir.set_reg(ra, ir.get_reg(rs) ^ ir.get_reg(rb));
    IRVariable overflow = ir.get_overflow();

    if (rc) emit_set_cr_flags_generic(ir, 0, ir.get_reg(ra));
}

private void emit_xori(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs  = to_gpr(opcode.bits(21, 25));
    GuestReg ra  = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    ir.set_reg(ra, ir.get_reg(rs) ^ imm);
}

private void emit_xoris(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg rs  = to_gpr(opcode.bits(21, 25));
    GuestReg ra  = to_gpr(opcode.bits(16, 20));
    int      imm = opcode.bits(0, 15);

    ir.set_reg(ra, ir.get_reg(rs) ^ (imm << 16));
}

private void emit_op_04(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp04SecondaryOpcode.PS_MR: emit_ps_mr(ir, opcode, ctx); break;

        default: unimplemented_opcode(opcode, ctx);
    }
}

private void emit_op_13(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp13SecondaryOpcode.BCCTR: emit_bcctr(ir, opcode, ctx); break;
        case PrimaryOp13SecondaryOpcode.BCLR:  emit_bclr (ir, opcode, ctx); break;
        case PrimaryOp13SecondaryOpcode.CRXOR: emit_crxor(ir, opcode, ctx); break;
        case PrimaryOp13SecondaryOpcode.ISYNC: emit_isync(ir, opcode, ctx); break;

        default: unimplemented_opcode(opcode, ctx);
    }
}

private void emit_op_1F(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp1FSecondaryOpcode.ADD:     emit_addx   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDC:    emit_addcx  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDCO:   emit_addcx  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDE:    emit_addex  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDEO:   emit_addex  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDO:    emit_addx   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDME:   emit_addmex (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDMEO:  emit_addmex (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDZE:   emit_addzex (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ADDZEO:  emit_addzex (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.AND:     emit_and    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ANDC:    emit_andc   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.CNTLZW:  emit_cntlzw (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.CMP:     emit_cmp    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.CMPL:    emit_cmpl   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DCBF:    emit_dcbf   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DCBI:    emit_dcbi   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DCBST:   emit_dcbst  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DIVW:    emit_divwx  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DIVWO:   emit_divwx  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DIVWU:   emit_divwux (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.DIVWUO:  emit_divwux (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.EQV:     emit_eqv    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.EXTSB:   emit_extsb  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.EXTSH:   emit_extsh  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.HLE:     emit_hle    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ICBI:    emit_icbi   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.LWZX:    emit_lwzx   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MFMSR:   emit_mfmsr  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MFSPR:   emit_mfspr  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MTMSR:   emit_mtmsr  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MTSPR:   emit_mtspr  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MULLW:   emit_mullwx (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MULLWO:  emit_mullwx (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MULHW:   emit_mulhw  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.MULHWU:  emit_mulhwu (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.NAND:    emit_nand   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.NEG:     emit_negx   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.NEGO:    emit_negx   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.NOR:     emit_nor    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.OR:      emit_or     (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.ORC:     emit_orc    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SLW:     emit_slw    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SRAW:    emit_sraw   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SRAWI:   emit_srawi  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SRW:     emit_srw    (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.STWX:    emit_stwx   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBF:    emit_subfx  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFO:   emit_subfx  (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFC:   emit_subfcx (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFCO:  emit_subfcx (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFE:   emit_subfex (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFEO:  emit_subfex (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFME:  emit_subfmex(ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFMEO: emit_subfmex(ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFZE:  emit_subfzex(ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SUBFZEO: emit_subfzex(ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.SYNC:    emit_sync   (ir, opcode, ctx); break;
        case PrimaryOp1FSecondaryOpcode.XOR:     emit_xor    (ir, opcode, ctx); break;

        default: unimplemented_opcode(opcode, ctx);
    }
}

private void emit_op_3B(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        case PrimaryOp3BSecondaryOpcode.FADDSX:   emit_faddsx  (ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FDIVSX:   emit_fdivsx  (ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FMADDSX:  emit_fmaddsx (ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FMSUBSX:  emit_fmsubsx (ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FMULSX:   emit_fmulsx  (ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FNMADDSX: emit_fnmaddsx(ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FNMSUBSX: emit_fnmsubsx(ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FRESX:    emit_fresx   (ir, opcode, ctx); break;
        case PrimaryOp3BSecondaryOpcode.FSUBSX:   emit_fsubsx  (ir, opcode, ctx); break;

        default: unimplemented_opcode(opcode, ctx);
    }
}

private void emit_op_3F(IR* ir, u32 opcode, JitContext ctx) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp3FSecondaryOpcode.FABSX:  emit_fabsx  (ir, opcode, ctx); return;
        case PrimaryOp3FSecondaryOpcode.FCTIWX: emit_fctiwx (ir, opcode, ctx); return;
        case PrimaryOp3FSecondaryOpcode.FMR:    emit_fmr    (ir, opcode, ctx); return;
        case PrimaryOp3FSecondaryOpcode.FNABSX: emit_fnabsx (ir, opcode, ctx); return;    
        case PrimaryOp3FSecondaryOpcode.FNEGX:  emit_fnegx  (ir, opcode, ctx); return;
        case PrimaryOp3FSecondaryOpcode.MTFSF:  emit_mtfsf  (ir, opcode, ctx); return;
        default: break;
    }

    secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        case PrimaryOp3FSecondaryOpcode.FADDX:   emit_faddx  (ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FDIVX:   emit_fdivx  (ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FMADDX:  emit_fmaddx (ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FMSUBX:  emit_fmsubx (ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FMULX:   emit_fmulx  (ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FNMADDX: emit_fnmaddx(ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FNMSUBX: emit_fnmsubx(ir, opcode, ctx); break;
        case PrimaryOp3FSecondaryOpcode.FSEL:    emit_fsel   (ir, opcode, ctx); break;
        default: unimplemented_opcode(opcode, ctx);
    }
}

public void emit(IR* ir, u32 opcode, JitContext ctx) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:   emit_addi  (ir, opcode, ctx); break;
        case PrimaryOpcode.ADDIC:  emit_addic (ir, opcode, ctx); break;
        case PrimaryOpcode.ADDIC_: emit_addic_(ir, opcode, ctx); break;
        case PrimaryOpcode.ADDIS:  emit_addis (ir, opcode, ctx); break;
        case PrimaryOpcode.ANDI:   emit_andi  (ir, opcode, ctx); break;
        case PrimaryOpcode.ANDIS:  emit_andis (ir, opcode, ctx); break;
        case PrimaryOpcode.B:      emit_b     (ir, opcode, ctx); break;
        case PrimaryOpcode.BC:     emit_bc    (ir, opcode, ctx); break;
        case PrimaryOpcode.CMPLI:  emit_cmpli (ir, opcode, ctx); break;
        case PrimaryOpcode.CMPI:   emit_cmpi  (ir, opcode, ctx); break;
        case PrimaryOpcode.LBZU:   emit_lbzu  (ir, opcode, ctx); break;
        case PrimaryOpcode.LFD:    emit_lfd   (ir, opcode, ctx); break;
        case PrimaryOpcode.LHZ:    emit_lhz   (ir, opcode, ctx); break;
        case PrimaryOpcode.LWZ:    emit_lwz   (ir, opcode, ctx); break;
        case PrimaryOpcode.LWZU:   emit_lwzu  (ir, opcode, ctx); break;
        case PrimaryOpcode.MULLI:  emit_mulli (ir, opcode, ctx); break;
        case PrimaryOpcode.ORI:    emit_ori   (ir, opcode, ctx); break;
        case PrimaryOpcode.ORIS:   emit_oris  (ir, opcode, ctx); break;
        case PrimaryOpcode.PSQ_L:  emit_psq_l (ir, opcode, ctx); break;
        case PrimaryOpcode.RLWIMI: emit_rlwimi(ir, opcode, ctx); break;
        case PrimaryOpcode.RLWINM: emit_rlwinm(ir, opcode, ctx); break;
        case PrimaryOpcode.RLWNM:  emit_rlwnm (ir, opcode, ctx); break;
        case PrimaryOpcode.SC:     emit_sc    (ir, opcode, ctx); break;
        case PrimaryOpcode.STB:    emit_stb   (ir, opcode, ctx); break;
        case PrimaryOpcode.STBU:   emit_stbu  (ir, opcode, ctx); break;
        case PrimaryOpcode.STH:    emit_sth   (ir, opcode, ctx); break;
        case PrimaryOpcode.STW:    emit_stw   (ir, opcode, ctx); break;
        case PrimaryOpcode.STWU:   emit_stwu  (ir, opcode, ctx); break;
        case PrimaryOpcode.SUBFIC: emit_subfic(ir, opcode, ctx); break;
        case PrimaryOpcode.XORI:   emit_xori  (ir, opcode, ctx); break;
        case PrimaryOpcode.XORIS:  emit_xoris (ir, opcode, ctx); break;

        case PrimaryOpcode.OP_04:  emit_op_04 (ir, opcode, ctx); break;
        case PrimaryOpcode.OP_13:  emit_op_13 (ir, opcode, ctx); break;
        case PrimaryOpcode.OP_1F:  emit_op_1F (ir, opcode, ctx); break;
        case PrimaryOpcode.OP_3B:  emit_op_3B (ir, opcode, ctx); break;
        case PrimaryOpcode.OP_3F:  emit_op_3F (ir, opcode, ctx); break;

        default: unimplemented_opcode(opcode, ctx);
    }
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