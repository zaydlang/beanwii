module emu.hw.broadway.jit.frontend.disassembler;

import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.frontend.helpers;
import emu.hw.broadway.jit.frontend.opcode;
import emu.hw.broadway.jit.frontend.paired_single;
import emu.hw.broadway.jit.ir.ir;
import util.bitop;
import util.log;
import util.number;

private void emit_add(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     oe = opcode.bit(10);
    bool     rc = opcode.bit(0);

    assert(!oe);
    assert(!rc);

    IRVariable result = ir.get_reg(ra) + ir.get_reg(rb);
    ir.set_reg(rd, result);
}

private void emit_addi(IR* ir, u32 opcode, u32 pc) {
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

private void emit_addic(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    emit_add_generic(
        ir,
        rd, ir.get_reg(ra), ir.get_reg(rb),
        false, // record bit
        true,  // XER CA
        false, // XER SO & OV
    );
}

private void emit_addic_(IR* ir, u32 opcode, u32 pc) {
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

private void emit_addis(IR* ir, u32 opcode, u32 pc) {
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

private void emit_b(IR* ir, u32 opcode, u32 pc) {
    bool aa = opcode.bit(1);
    bool lk = opcode.bit(0);
    int  li = opcode.bits(2, 25);

    u32 branch_address = sext_32(li, 24) << 2;
    if (!aa) branch_address += pc;

    if (lk) ir.set_reg(GuestReg.LR, pc + 4);

    ir.set_reg(GuestReg.PC, branch_address);
}

private void emit_bc(IR* ir, u32 opcode, u32 pc) {
    bool lk = opcode.bit(0);
    bool aa = opcode.bit(1);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);
    int  bd = opcode.bits(2, 15);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi);

    if (lk) ir.set_reg(GuestReg.LR, pc + 4);

    ir._if(cond_ok, () {
        if (lk) {
            ir.set_reg(GuestReg.LR, pc + 4);
        }

        if (aa) {
            ir.set_reg(GuestReg.PC, ir.constant(sext_32(bd, 14) << 2));
        } else {
            ir.set_reg(GuestReg.PC, pc + (sext_32(bd, 14) << 2));
        }
    });
}

private void emit_bcctr(IR* ir, u32 opcode, u32 pc) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    assert(opcode.bits(11, 15) == 0);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    ir._if(cond_ok, () { 
        if (lk) ir.set_reg(GuestReg.LR, pc + 4);

        // TODO: insert an assert into the JIT'ted code that checks that LR is never un-aligned
        ir.set_reg(GuestReg.PC, ir.get_reg(GuestReg.CTR));
    });
}

private void emit_bclr(IR* ir, u32 opcode, u32 pc) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    IRVariable cond_ok = emit_evaluate_condition(ir, bo, bi); 
    
    ir._if(cond_ok, () { 
        if (lk) ir.set_reg(GuestReg.LR, pc + 4);

        // TODO: insert an assert into the JIT'ted code that checks that LR is never un-aligned
        ir.set_reg(GuestReg.PC, ir.get_reg(GuestReg.LR));
    });
}

private void emit_cntlzw(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));

    assert(opcode.bits(11, 15) == 0);

    ir.set_reg(ra, ir.get_reg(rs).clz());
}

private void emit_cmp(IR* ir, u32 opcode, u32 pc) {
    int crf_d = opcode.bits(23, 25);
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0)  == 0);
    assert(opcode.bit(21) == 0);
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

private void emit_cmpl(IR* ir, u32 opcode, u32 pc) {
    int crf_d = opcode.bits(23, 25);
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    assert(opcode.bit(0)  == 0);
    assert(opcode.bit(21) == 0);
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

private void emit_cmpli(IR* ir, u32 opcode, u32 pc) {
    int  crf_d = opcode.bits(23, 25);
    int  uimm  = opcode.bits(0, 15);

    assert(opcode.bit(21) == 0);
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

private void emit_cmpi(IR* ir, u32 opcode, u32 pc) {
    int crf_d    = opcode.bits(23, 25);
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int simm    = sext_32(opcode.bits(0, 15), 16);

    assert(opcode.bit(21) == 0);
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

private void emit_crxor(IR* ir, u32 opcode, u32 pc) {
    int crbD = 31 - opcode.bits(21, 25);
    int crbA = 31 - opcode.bits(16, 20);
    int crbB = 31 - opcode.bits(11, 15);

    assert(opcode.bit(0) == 0);

    IRVariable cr = ir.get_reg(GuestReg.CR);
    cr = cr & ~(1 << crbD);
    cr = cr | ((((cr >> crbA) & 1) ^ ((cr >> crbB) & 1)) << crbD);
    ir.set_reg(GuestReg.CR, cr);
}

private void emit_dcbf(IR* ir, u32 opcode, u32 pc) {
    // i'm just not going to emulate cache stuff
}

private void emit_dcbi(IR* ir, u32 opcode, u32 pc) {
    // i'm just not going to emulate cache stuff
}

private void emit_dcbst(IR* ir, u32 opcode, u32 pc) {
    // TODO: do i really have to emulate this opcode? it sounds awful for performance.
    // for now i'll just do this silly hack...
    assert(opcode.bits(21, 25) == 0);
}

private void emit_hle(IR* ir, u32 opcode, u32 pc) {
    int hle_function_id = opcode.bits(21, 25);
    ir.run_hle_func(hle_function_id);
}

private void emit_icbi(IR* ir, u32 opcode, u32 pc) {
    // i'm just not going to emulate cache stuff
}

private void emit_isync(IR* ir, u32 opcode, u32 pc) {
    // not needed for emulation
}

private void emit_lbzu(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    assert(ra != 0);
    assert(ra != rd);

    IRVariable address = ir.get_reg(ra) + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u8(address));
    ir.set_reg(ra, address);
}

private void emit_lfd(IR* ir, u32 opcode, u32 pc) {
    // GuestReg rd = to_fpr(opcode.bits(21, 25));
    // GuestReg ra = to_gpr(opcode.bits(16, 20));
    // int d       = sext_32(opcode.bits(0, 15));

    // ir.read_u64(rd, ir.get_reg(ra));
}

private void emit_lhz(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u16(address));
}

private void emit_lwz(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));
}

private void emit_lwzu(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int d       = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(d, 16);
    ir.set_reg(rd, ir.read_u32(address));
    ir.set_reg(ra, address);
}

private void emit_lwzx(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + ir.get_reg(rb);
    ir.set_reg(rd, ir.read_u32(address));
}

private void emit_mfmsr(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(rd, ir.get_reg(GuestReg.MSR));
}

private void emit_mfspr(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);

    // assert(spr == 0b1000_00000);

    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(rd, ir.get_reg(src));
}

private void emit_mtmsr(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    ir.set_reg(GuestReg.MSR, ir.get_reg(rs));
}

private void emit_mtspr(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    int spr     = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);
    
    GuestReg src = get_spr_from_encoding(spr);
    ir.set_reg(src, ir.get_reg(rd));
}

private void emit_nor(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    assert(rc == 0);

    IRVariable result = ~(ir.get_reg(rs) | ir.get_reg(rb));
    ir.set_reg(ra, result);
}

private void emit_or(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    assert(rc == 0);

    IRVariable result = ir.get_reg(rs) | ir.get_reg(rb);
    ir.set_reg(ra, result);
}

private void emit_ori(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15);

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);
}

private void emit_oris(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int uimm = opcode.bits(0, 15) << 16;

    IRVariable result = ir.get_reg(rs) | uimm;
    ir.set_reg(ra, result);
}

private void emit_rlwinm(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int      sh = opcode.bits(11, 15);
    int      mb = 31 - opcode.bits(6, 10);
    int      me = 31 - opcode.bits(1, 5);
    bool     rc = opcode.bit(0);

    assert(mb >= me);
    int mask = cast(int) (((cast(u64) 1) << (cast(u64) (mb - me + 1))) - 1) << me;

    IRVariable result = ir.get_reg(rs);
    result = result.rol(sh) & mask;
    ir.set_reg(ra, result);

    if (rc) {
        emit_set_cr_lt(ir, 0, result.lesser_signed(ir.constant(0)));
        emit_set_cr_gt(ir, 0, result.greater_signed(ir.constant(0)));
        emit_set_cr_eq(ir, 0, result.equals(ir.constant(0)));
        emit_set_cr_so(ir, 0, ir.constant(0)); // TODO: what does overflow even mean in the context of rlwinm????
    }
}

private void emit_sc(IR* ir, u32 opcode, u32 pc) {
    // apparently syscalls are only used for "sync" and "isync" on the Wii
    // and that's something i don't need to emulate
}

private void emit_slw(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    assert(rc == 0);

    IRVariable shift = ir.get_reg(rb) & 0x3F;
    IRVariable result = ir.constant(0);

    ir._if(shift.lesser_unsigned(ir.constant(32)),
        () {
            result = ir.get_reg(rs) << shift;
        },
    );

    ir.set_reg(ra, result);
}

private void emit_sraw(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    // 7c831e30 
    // 011111 00100 00011 00011 110 0011 0000

    assert(rc == 0);

    IRVariable shift = ir.get_reg(rb) & 0x3F;
    ir._if(shift.greater_unsigned(ir.constant(31)),
        () {
            shift = ir.constant(31);
        }
    );

    IRVariable result = ir.get_reg(rs) >> shift;
    ir.set_reg(ra, result);
}

private void emit_srw(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    assert(rc == 0);

    IRVariable shift = ir.get_reg(rb) & 0x3F;
    ir._if(shift.greater_unsigned(ir.constant(31)),
        () {
            shift = ir.constant(31);
        }
    );

    IRVariable result = ir.get_reg(rs) >>> shift;
    ir.set_reg(ra, result);
}

private void emit_stb(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u8(address, ir.get_reg(rs));
}

private void emit_stbu(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.set_reg(ra, address);
    ir.write_u8(address, ir.get_reg(rs));
}

private void emit_sth(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    
    if (ra == 0) {
        ir.write_u16(ir.constant(sext_32(offset, 16)), ir.get_reg(rs));
    } else {
        ir.write_u16(ir.get_reg(ra) + sext_32(offset, 16), ir.get_reg(rs));
    }
}

private void emit_stw(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
}

private void emit_stwu(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    int offset  = opcode.bits(0, 15);

    assert(ra != 0);

    IRVariable address = ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
    ir.set_reg(ra, address);
}

private void emit_subf(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    assert(!rc);

    IRVariable result = ir.get_reg(rb) - ir.get_reg(ra);
    ir.set_reg(rd, result);
}

private void emit_sync(IR* ir, u32 opcode, u32 pc) {
    // not needed for emulation
}

private void emit_xor(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = to_gpr(opcode.bits(21, 25));
    GuestReg ra = to_gpr(opcode.bits(16, 20));
    GuestReg rb = to_gpr(opcode.bits(11, 15));
    bool     rc = opcode.bit(0);

    assert(!rc);

    ir.set_reg(ra, ir.get_reg(rs) ^ ir.get_reg(rb));
}

private void emit_op_13(IR* ir, u32 opcode, u32 pc) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp13SecondaryOpcode.BCCTR: emit_bcctr(ir, opcode, pc); break;
        case PrimaryOp13SecondaryOpcode.BCLR:  emit_bclr (ir, opcode, pc); break;
        case PrimaryOp13SecondaryOpcode.CRXOR: emit_crxor(ir, opcode, pc); break;
        case PrimaryOp13SecondaryOpcode.ISYNC: emit_isync(ir, opcode, pc); break;

        default: unimplemented_opcode(opcode, pc);
    }
}

private void emit_op_1F(IR* ir, u32 opcode, u32 pc) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp1FSecondaryOpcode.ADD:    emit_add   (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.CNTLZW: emit_cntlzw(ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.CMP:    emit_cmp   (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.CMPL:   emit_cmpl  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.DCBF:   emit_dcbf  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.DCBI:   emit_dcbi  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.DCBST:  emit_dcbst (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.HLE:    emit_hle   (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.ICBI:   emit_icbi  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.LWZX:   emit_lwzx  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.MFMSR:  emit_mfmsr (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.MFSPR:  emit_mfspr (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.MTMSR:  emit_mtmsr (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.MTSPR:  emit_mtspr (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.NOR:    emit_nor   (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.OR:     emit_or    (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.SLW:    emit_slw   (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.SRAW:   emit_sraw  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.SRW:    emit_srw   (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.SUBF:   emit_subf  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.SYNC:   emit_sync  (ir, opcode, pc); break;
        case PrimaryOp1FSecondaryOpcode.XOR:    emit_xor   (ir, opcode, pc); break;

        default: unimplemented_opcode(opcode, pc);
    }
}

public void emit(IR* ir, u32 opcode, u32 pc) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:   emit_addi  (ir, opcode, pc); break;
        case PrimaryOpcode.ADDIC:  emit_addic (ir, opcode, pc); break;
        case PrimaryOpcode.ADDIC_: emit_addic_(ir, opcode, pc);  break;
        case PrimaryOpcode.ADDIS:  emit_addis (ir, opcode, pc); break;
        case PrimaryOpcode.B:      emit_b     (ir, opcode, pc); break;
        case PrimaryOpcode.BC:     emit_bc    (ir, opcode, pc); break;
        case PrimaryOpcode.CMPLI:  emit_cmpli (ir, opcode, pc); break;
        case PrimaryOpcode.CMPI:   emit_cmpi  (ir, opcode, pc); break;
        case PrimaryOpcode.LBZU:   emit_lbzu  (ir, opcode, pc); break;
        case PrimaryOpcode.LHZ:    emit_lhz   (ir, opcode, pc); break;
        case PrimaryOpcode.LWZ:    emit_lwz   (ir, opcode, pc); break;
        case PrimaryOpcode.LWZU:   emit_lwzu  (ir, opcode, pc); break;
        case PrimaryOpcode.ORI:    emit_ori   (ir, opcode, pc); break;
        case PrimaryOpcode.ORIS:   emit_oris  (ir, opcode, pc); break;
        case PrimaryOpcode.PSQ_L:  emit_psq_l (ir, opcode, pc); break;
        case PrimaryOpcode.RLWINM: emit_rlwinm(ir, opcode, pc); break;
        case PrimaryOpcode.SC:     emit_sc    (ir, opcode, pc); break;
        case PrimaryOpcode.STB:    emit_stb   (ir, opcode, pc); break;
        case PrimaryOpcode.STBU:   emit_stbu  (ir, opcode, pc); break;
        case PrimaryOpcode.STH:    emit_sth   (ir, opcode, pc); break;
        case PrimaryOpcode.STW:    emit_stw   (ir, opcode, pc); break;
        case PrimaryOpcode.STWU:   emit_stwu  (ir, opcode, pc); break;

        case PrimaryOpcode.OP_13:  emit_op_13 (ir, opcode, pc); break;
        case PrimaryOpcode.OP_1F:  emit_op_1F (ir, opcode, pc); break;

        default: unimplemented_opcode(opcode, pc);
    }
}

private void unimplemented_opcode(u32 opcode, u32 pc) {
    import capstone;

    auto cs = create(Arch.ppc, ModeFlags(Mode.bit32));
    auto res = cs.disasm((cast(ubyte*) &opcode)[0 .. 4], pc);
    foreach (instr; res) {
        log_jit("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
    }

    error_jit("Unimplemented opcode: 0x%08x (at PC 0x%08x)", opcode, pc);
}