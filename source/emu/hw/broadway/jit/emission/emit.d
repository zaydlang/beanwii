module emu.hw.broadway.jit.emission.emit;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.flags;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.helpers;
import emu.hw.broadway.jit.emission.opcode;
import emu.hw.broadway.jit.emission.floating_point;
import emu.hw.broadway.jit.emission.paired_singles;
import emu.hw.broadway.state;
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
    
    set_flags(code, true, rc, oe, rd, rd, rb, ra, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addex(Code code, u32 opcode) {
    code.reserve_register(ecx);
    code.reserve_register(eax);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto rd       = code.get_reg(guest_rd);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    code.mov(eax, code.get_address(GuestReg.XER));
    code.shr(eax, 21);
    code.sahf();

    code.mov(rd, ra);
    code.adc(rd, rb);
    code.set_reg(guest_rd, rd);
    
    set_flags(code, true, rc, oe, rd, rd, ra, rb, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addi(Code code, u32 opcode) {
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

private EmissionAction emit_addic(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  simm     = sext_32(opcode.bits(0, 15), 16);
    auto ra       = code.get_reg(guest_ra);

    code.add(ra, simm);
    code.set_reg(guest_rd, ra);
    
    set_flags(code, true, false, false, ra, ra, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addic_(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  simm     = sext_32(opcode.bits(0, 15), 16);
    auto ra       = code.get_reg(guest_ra);

    code.add(ra, simm);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, true, false, ra, ra, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
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

private EmissionAction emit_addmex(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto ra       = code.get_reg(guest_ra);
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);

    code.mov(eax, code.get_address(GuestReg.XER));
    code.shr(eax, 29);
    code.and(eax, 1);
    code.sub(eax, 1);

    code.add(ra, eax);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, rc, oe, ra, ra, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addx(Code code, u32 opcode) {
    code.reserve_register(ecx);
    code.reserve_register(eax);

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
    
    set_flags(code, false, rc, oe, rd, rd, ra, rb, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_addzex(Code code, u32 opcode) {
    code.reserve_register(ecx);
    code.reserve_register(eax);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);

    code.mov(eax, code.get_address(GuestReg.XER));
    code.shr(eax, 21);
    code.sahf();

    code.adc(ra, 0);
    code.set_reg(guest_rd, ra);
    
    set_flags(code, true, rc, oe, ra, ra, code.allocate_register(), eax, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_and(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.and(rs, rb);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_andc(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.not(rb);
    code.and(rs, rb);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_andi(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int uimm      = opcode.bits(0, 15);

    auto rs = code.get_reg(guest_rs);
    code.and(rs, uimm);
    code.set_reg(guest_ra, rs);
    
    set_flags(code, false, true, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_andis(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int uimm      = opcode.bits(0, 15) << 16;

    auto rs = code.get_reg(guest_rs);
    code.and(rs, uimm);
    code.set_reg(guest_ra, rs);
    
    set_flags(code, false, true, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_b(Code code, u32 opcode) {
    bool aa             = opcode.bit(1);
    bool lk             = opcode.bit(0);
    int  li             = opcode.bits(2, 25);
    u32  branch_address = sext_32(li, 24) << 2;

    auto pc = code.get_reg(GuestReg.PC);
    auto lr = code.allocate_register();

    if (lk) {
        code.lea(lr, dword [pc + 4]);
        code.set_reg(GuestReg.LR, lr);
    }

    if (!aa) {
        code.add(pc, branch_address);
    }

    code.set_reg(GuestReg.PC, pc);

    return EmissionAction.STOP;
}

private EmissionAction emit_bc(Code code, u32 opcode) {
    bool aa = opcode.bit(1);
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);
    int  bd = opcode.bits(2, 15);

    auto tmp = code.allocate_register();

    is_cond_ok(code, bo, bi, tmp);

    auto no_branch = code.fresh_label();
    auto end       = code.fresh_label();
    code.test(tmp, 1);
    code.jz(no_branch);

    if (lk) {
        auto pc = code.get_reg(GuestReg.PC);
        code.lea(pc, dword [pc + 4]);
        code.set_reg(GuestReg.LR, pc);
    }

    if (aa) {
        code.mov(tmp, sext_32(bd, 14) << 2);
        code.set_reg(GuestReg.PC, tmp);
    } else {
        auto address = code.get_reg(GuestReg.PC);
        code.add(address, sext_32(bd, 14) << 2);
        code.set_reg(GuestReg.PC, address);
    }

    code.jmp(end);

code.L(no_branch);
    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);

code.L(end);
    return EmissionAction.STOP;
}

private EmissionAction emit_bcctr(Code code, u32 opcode) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    assert(opcode.bits(11, 15) == 0);

    auto tmp = code.allocate_register();
    is_cond_ok(code, bo, bi, tmp);

    auto no_branch = code.fresh_label();
    auto end       = code.fresh_label();

    code.test(tmp, 1);
    code.jz(no_branch);

    if (lk) {
        auto pc = code.get_reg(GuestReg.PC);
        code.lea(pc, dword [pc + 4]);
        code.set_reg(GuestReg.LR, pc);
    }

    auto ctr = code.get_reg(GuestReg.CTR);
    code.set_reg(GuestReg.PC, ctr);

    code.jmp(end);

code.L(no_branch);
    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);

code.L(end);
    return EmissionAction.STOP;
}

private EmissionAction emit_bclr(Code code, u32 opcode) {
    bool lk = opcode.bit(0);
    int  bo = opcode.bits(21, 25);
    int  bi = opcode.bits(16, 20);

    assert(opcode.bits(11, 15) == 0);

    auto tmp = code.allocate_register();
    is_cond_ok(code, bo, bi, tmp);

    auto no_branch = code.fresh_label();
    auto end       = code.fresh_label();

    code.test(tmp, 1);
    code.jz(no_branch);

    if (lk) {
        auto pc = code.get_reg(GuestReg.PC);
        code.lea(pc, dword [pc + 4]);
        code.set_reg(GuestReg.LR, pc);
    }

    auto lr = code.get_reg(GuestReg.LR);
    code.set_reg(GuestReg.PC, lr);

    code.jmp(end);

code.L(no_branch);
    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);

code.L(end);
    return EmissionAction.STOP;
}

private EmissionAction emit_cntlzw(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);

    assert(opcode.bits(11, 15) == 0);

    code.lzcnt(rs, rs);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_cmp(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto crf_d    = opcode.bits(23, 25);

    assert(opcode.bit(0)  == 0);
    assert(opcode.bit(22) == 0);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);

    do_cmp(code, CmpType.Signed, ra, rb, crf_d);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_cmpl(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto crf_d    = opcode.bits(23, 25);

    assert(opcode.bit(0)  == 0);
    assert(opcode.bit(22) == 0);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);

    do_cmp(code, CmpType.Unsigned, ra, rb, crf_d);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_cmpli(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  uimm     = opcode.bits(0, 15);
    auto crf_d    = opcode.bits(23, 25);

    assert(opcode.bit(22) == 0);

    auto ra = code.get_reg(guest_ra);

    do_cmp(code, CmpType.Unsigned, ra, uimm, crf_d);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_cmpi(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  imm      = sext_32(opcode.bits(0, 15), 16);
    auto crf_d    = opcode.bits(23, 25);

    assert(opcode.bit(22) == 0);

    auto ra = code.get_reg(guest_ra);

    do_cmp(code, CmpType.Signed, ra, imm, crf_d);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_crxor(Code code, u32 opcode) {
    auto crbD = get_cr_index(opcode.bits(21, 25));
    auto crbA = get_cr_index(opcode.bits(16, 20));
    auto crbB = get_cr_index(opcode.bits(11, 15));
    auto cr   = code.get_reg(GuestReg.CR);

    assert(opcode.bit(0) == 0);

    auto tmp1 = code.allocate_register();
    
    code.mov(tmp1, cr);
    code.shr(tmp1, crbA);
    code.and(tmp1, 1);

    code.shr(cr, crbB);
    code.and(cr, 1);

    code.xor(cr, tmp1);

    code.shl(cr, crbD);
    code.and(code.get_address(GuestReg.CR), ~(1 << crbD));
    code.or(code.get_address(GuestReg.CR), cr);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_dcbf(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_dcbi(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_dcbst(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_divwx(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);
    code.reserve_register(edx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);
    
    auto good_division = code.fresh_label();
    auto bad_division  = code.fresh_label();
    auto end           = code.fresh_label();

    code.cmp(rb, 0);
    code.je(bad_division);
    code.cmp(ra, 0x80000000);
    code.jne(good_division);
    code.cmp(ra, 0xFFFFFFFF);
    code.jne(good_division);

code.L(good_division);    
    code.mov(eax, ra);
    code.cdq();
    code.idiv(rb);
    code.mov(ra, eax);
    code.set_reg(guest_rd, ra);
    set_division_flags(code, rc, oe, ra, rb, false);
    code.jmp(end);

code.L(bad_division);
    code.sar(ra, 31);
    code.set_reg(guest_rd, ra);
    set_division_flags(code, rc, oe, ra, rb, true);

code.L(end);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_divwux(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);
    code.reserve_register(edx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);
    
    auto good_division = code.fresh_label();
    auto bad_division  = code.fresh_label();
    auto end           = code.fresh_label();

    code.cmp(rb, 0);
    code.je(bad_division);
    code.cmp(ra, 0x80000000);
    code.jne(good_division);
    code.cmp(ra, 0xFFFFFFFF);
    code.jne(good_division);

code.L(good_division);    
    code.mov(rax, ra.cvt64());
    code.cqo();
    code.div(rb.cvt64());
    code.mov(ra, eax);
    code.set_reg(guest_rd, ra);
    set_division_flags(code, rc, oe, ra, rb, false);
    code.jmp(end);

code.L(bad_division);
    code.xor(ra, ra);
    code.set_reg(guest_rd, ra);
    set_division_flags(code, rc, oe, ra, rb, true);

code.L(end);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_eqv(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.xor(rs, rb);
    code.not(rs);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_extsb(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);

    assert(opcode.bits(11, 15) == 0);

    code.movsx(rs, rs.cvt8());
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_extsh(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);

    assert(opcode.bits(11, 15) == 0);

    code.movsx(rs, rs.cvt16());
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_hle(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    
    auto hle_function_id = opcode.bits(21, 25);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.hle_handler_context);
        code.mov(esi, hle_function_id);
        code.mov(rax, cast(u64) code.config.hle_handler);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.STOP;
}

private EmissionAction emit_icbi(Code code, u32 opcode) {
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    assert(opcode.bits(21, 25) == 0);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    code.mov(dword [rdi + BroadwayState.icbi_address.offsetof], ra);
    code.mov(byte_ [rdi + BroadwayState.icache_flushed.offsetof], 1);

    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);

    return EmissionAction.STOP;
}

private EmissionAction emit_isync(Code code, u32 opcode) {
    code.mov(byte_ [rdi + BroadwayState.icache_flushed.offsetof], 1);

    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);

    return EmissionAction.STOP;
}

private EmissionAction emit_lbz(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  d        = sext_32(opcode.bits(0, 15), 16);
    auto ra       = code.get_reg(guest_ra);

    assert(guest_ra != GuestReg.R0);

    code.mov(esi, ra);
    code.add(esi, d);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);

        code.mov(rax, cast(u64) code.config.read_handler8);
        code.call(rax);
        code.movzx(eax, al);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lbzu(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  d        = sext_32(opcode.bits(0, 15), 16);
    auto ra       = code.get_reg(guest_ra);

    assert(guest_ra != GuestReg.R0);
    assert(guest_ra != guest_rd);

    code.mov(esi, ra);
    code.add(esi, d);
    code.set_reg(guest_ra, esi);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);

        code.mov(rax, cast(u64) code.config.read_handler8);
        code.call(rax);
        code.movzx(eax, al);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lbzx(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    code.mov(esi, ra);
    code.add(esi, rb);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);

        code.mov(rax, cast(u64) code.config.read_handler8);
        code.call(rax);
        code.movzx(eax, al);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lha(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  d        = sext_32(opcode.bits(0, 15), 16);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, d);

        code.mov(rax, cast(u64) code.config.read_handler16);
        code.call(rax);
        code.movsx(eax, ax);
    code.exit_stack_alignment_context();
    code.pop(rdi);
    
    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lhz(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  d        = sext_32(opcode.bits(0, 15), 16);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, d);

        code.mov(rax, cast(u64) code.config.read_handler16);
        code.call(rax);
        code.movzx(eax, ax);
    code.exit_stack_alignment_context();
    code.pop(rdi);
    
    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lhzu(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto ra       = code.get_reg(guest_ra);
    auto d        = sext_32(opcode.bits(0, 15), 16);

    assert(guest_ra != GuestReg.R0);
    assert(guest_ra != guest_rd);

    code.mov(esi, ra);
    code.add(esi, d);
    code.set_reg(guest_ra, esi);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(rax, cast(u64) code.config.read_handler16);

        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);
    
    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lmw(Code code, u32 opcode) {
    // read registers from rd to r31
    code.reserve_register(esi);
    code.reserve_register(eax);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  d        = sext_32(opcode.bits(0, 15), 16);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
        for (int i = opcode.bits(21, 25); i < 32; i++) {
            code.push(ra);
            code.mov(esi, ra);
            code.add(esi, d);

            code.enter_stack_alignment_context();
            code.mov(rdi, cast(u64) code.config.mem_handler_context);
            code.mov(rax, cast(u64) code.config.read_handler32);
            code.call(rax);
            code.exit_stack_alignment_context();

            code.pop(ra);
            code.add(ra, 4);

            code.pop(rdi);
            code.set_reg(i.to_gpr, eax);
            code.push(rdi);

        }
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lwz(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  d        = sext_32(opcode.bits(0, 15), 16);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, d);

        code.mov(rax, cast(u64) code.config.read_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lwzu(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto ra       = code.get_reg(guest_ra);
    auto d        = sext_32(opcode.bits(0, 15), 16);

    assert(guest_ra != GuestReg.R0);
    assert(guest_ra != guest_rd);

    code.mov(esi, ra);
    code.add(esi, d);
    code.set_reg(guest_ra, esi);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(rax, cast(u64) code.config.read_handler32);

        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);
    
    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lhzx(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    Reg32 rb = code.get_reg(guest_rb);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, rb);

        code.mov(rax, cast(u64) code.config.read_handler16);
        code.call(rax);
        code.mov(eax, ax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_lwzx(Code code, u32 opcode) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    Reg32 rb = code.get_reg(guest_rb);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, rb);

        code.mov(rax, cast(u64) code.config.read_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mfcr(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto msr      = code.get_reg(GuestReg.CR);

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    code.set_reg(guest_rd, msr);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mfmsr(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto msr      = code.get_reg(GuestReg.MSR);

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    code.set_reg(guest_rd, msr);

    return EmissionAction.CONTINUE;
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
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mfspr(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto spr      = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);

    assert(opcode.bit(0) == 0);

    GuestReg src = get_spr_from_encoding(spr);
    auto reg = code.get_reg(src);
    code.set_reg(guest_rd, reg);

    // TODO: make this not shit
    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);
    return EmissionAction.STOP;
}

private EmissionAction emit_mftb(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    int tb_id = opcode.bits(16, 20) | (opcode.bits(11, 15) << 5);

    GuestReg tb_reg;
    switch (tb_id) {
        case 268: tb_reg = GuestReg.TBL; break;
        case 269: tb_reg = GuestReg.TBU; break;
        default: assert(0);
    }

    auto reg = code.get_reg(tb_reg);
    code.set_reg(guest_rd, reg);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mtcrf(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto crm      = opcode.bits(12, 19);

    assert(opcode.bit(20) == 0);
    assert(opcode.bit(11) == 0);
    assert(opcode.bit(0) == 0);

    u32 mask = 0;
    for (int i = 0; i < 8; i++) {
        if (crm.bit(i)) {
            mask |= 0xFF << (7 - i);
        }
    }

    auto reg = code.get_reg(guest_rs);
    code.and(code.get_address(GuestReg.CR), ~mask);
    code.and(reg, mask);
    code.or(code.get_address(GuestReg.CR), reg);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mtmsr(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto rs       = code.get_reg(guest_rs);

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 20) == 0b00000_00000);

    code.set_reg(GuestReg.MSR, rs);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mtspr(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto spr      = opcode.bits(11, 15) << 5 | opcode.bits(16, 20);
    auto rd       = code.get_reg(guest_rd);
    assert(opcode.bit(0) == 0);

    GuestReg sysreg = get_spr_from_encoding(spr);
    code.set_reg(sysreg, rd);

    // TODO: make this not shit
    auto pc = code.get_reg(GuestReg.PC);
    code.add(pc, 4);
    code.set_reg(GuestReg.PC, pc);
    return EmissionAction.STOP;
}

private EmissionAction emit_mtsr(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto sr       = opcode.bits(16, 19);

    assert(opcode.bit(0) == 0);
    assert(opcode.bits(11, 15) == 0);
    assert(opcode.bit(20) == 0);

    auto rs = code.get_reg(guest_rs);
    code.mov(dword [rdi + (cast(int) BroadwayState.sr.offsetof + 4 * sr)], rs);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mulli(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(edx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  simm     = sext_32(opcode.bits(0, 15), 16);
    auto ra       = code.get_reg(guest_ra);

    code.mov(eax, ra);
    code.mov(edx, simm);
    code.imul(edx);
    code.set_reg(guest_rd, eax);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mullwx(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(edx);
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    code.mov(eax, ra);
    code.imul(eax, rb);
    code.set_reg(guest_rd, eax);

    set_flags(code, false, rc, oe, eax, eax, ra, rb, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mulhw(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(edx);
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    code.mov(eax, ra);
    code.imul(rb);
    code.set_reg(guest_rd, edx);

    set_flags(code, false, rc, oe, edx, edx, ra, rb, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_mulhwu(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(edx);
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);
    auto rb       = code.get_reg(guest_rb);

    code.mov(eax, ra);
    code.mul(rb);
    code.set_reg(guest_rd, edx);

    set_flags(code, false, rc, oe, edx, edx, ra, rb, 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_nand(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.and(rs, rb);
    code.not(rs);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_negx(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool oe       = opcode.bit(10);
    bool rc       = opcode.bit(0);
    auto ra       = code.get_reg(guest_ra);

    assert(opcode.bits(11, 15) == 0);

    code.neg(ra);
    code.set_reg(guest_rd, ra);
    
    set_flags(code, false, rc, oe, ra, ra, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_nor(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.or(rs, rb);
    code.not(rs);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_or(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.or(rs, rb);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_orc(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);

    auto rs = code.get_reg(guest_rs);
    auto rb = code.get_reg(guest_rb);

    code.not(rb);
    code.or(rs, rb);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_ori(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  uimm     = opcode.bits(0, 15);
    auto rs = code.get_reg(guest_rs);
    
    code.or(rs, uimm);
    code.set_reg(guest_ra, rs);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_oris(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  uimm     = opcode.bits(0, 15) << 16;
    auto rs = code.get_reg(guest_rs);
    
    code.or(rs, uimm);
    code.set_reg(guest_ra, rs);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_rfi(Code code, u32 opcode) {
    auto srr1 = code.get_reg(GuestReg.SRR1);
    auto magic = 0b1000_0111_1100_0000_1111_1111_0111_0011;

    code.and(srr1, magic);
    code.and(code.get_address(GuestReg.MSR), ~magic);
    code.and(code.get_address(GuestReg.MSR), ~(1 << 18));
    code.or(code.get_address(GuestReg.MSR), srr1);

    auto pc = code.get_reg(GuestReg.SRR0);
    code.set_reg(GuestReg.PC, pc);

    return EmissionAction.STOP;
}

private EmissionAction emit_rlwimi(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  sh       = opcode.bits(11, 15);
    int  mb       = opcode.bits(6, 10);
    int  me       = opcode.bits(1, 5);
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto ra       = code.get_reg(guest_ra);

    int mask = generate_rlw_mask(mb, me);

    code.rol(rs, sh);
    code.and(rs, mask);
    code.and(ra, ~mask);
    code.or(ra, rs);
    code.set_reg(guest_ra, ra);

    set_flags(code, false, rc, false, ra, ra, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_rlwinm(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  sh       = opcode.bits(11, 15);
    int  mb       = opcode.bits(6, 10);
    int  me       = opcode.bits(1, 5);
    bool rc       = opcode.bit(0);
    auto rs = code.get_reg(guest_rs);

    int mask = generate_rlw_mask(mb, me);

    code.rol(rs, sh);
    code.and(rs, mask);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_rlwnm(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    int  mb       = opcode.bits(6, 10);
    int  me       = opcode.bits(1, 5);
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    int mask = generate_rlw_mask(mb, me);

    code.mov(cl, rb);
    code.rol(rs, cl);
    code.and(rs, mask);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_sc(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_slw(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.and(rb, 0x3F);
    code.mov(cl, rb);
    code.shl(rs, cl);
    code.xor(ecx, ecx);
    code.cmp(rb, 31);
    code.cmova(rs, ecx);

    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_sraw(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    auto tmp = code.allocate_register();

    code.and(rb, 0x3F);
    code.cmp(rb, 31);
    code.mov(ecx, 31);
    code.cmova(rb, ecx);

    code.cmp(rs, 0);
    code.setl(tmp.cvt8());
    code.bsf(ecx, rs);
    code.cmp(ecx, rb);
    code.setl(cl);
    code.and(tmp, ecx);
    code.shl(tmp, 29);

    code.mov(cl, rb);
    code.sar(rs, cl);

    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);
    
    code.and(code.get_address(GuestReg.XER), 0xdfff_ffff);
    code.or(code.get_address(GuestReg.XER), tmp);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_srawi(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  sh       = opcode.bits(11, 15);
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);

    auto tmp = code.allocate_register();

    code.cmp(rs, 0);
    code.setl(tmp.cvt8());
    code.bsf(ecx, rs);
    code.cmp(ecx, sh);
    code.setl(cl);
    code.and(tmp, ecx);
    code.shl(tmp, 29);

    code.sar(rs, sh);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, code.allocate_register(), code.allocate_register(), 0);
    
    code.and(code.get_address(GuestReg.XER), 0xdfff_ffff);
    code.or(code.get_address(GuestReg.XER), tmp);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_srw(Code code, u32 opcode) {
    code.reserve_register(ecx);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.and(rb, 0x3F);
    code.mov(cl, rb);
    code.shr(rs, cl);
    code.xor(ecx, ecx);
    code.cmp(rb, 31);
    code.cmova(rs, ecx);

    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stb(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  offset   = sext_32(opcode.bits(0, 15), 16);
    auto rs       = code.get_reg(guest_rs);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, offset);
        code.movzx(edx, rs.cvt8());
        code.mov(rax, cast(u64) code.config.write_handler8);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stbu(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  offset   = sext_32(opcode.bits(0, 15), 16);

    assert(guest_ra != GuestReg.R0);

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_reg(guest_rs);

    code.mov(esi, ra);
    code.add(esi, offset);
    code.set_reg(guest_ra, esi);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(edx, rs.cvt8());

        code.mov(rax, cast(u64) code.config.write_handler8);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_sth(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  offset   = sext_32(opcode.bits(0, 15), 16);
    auto rs       = code.get_reg(guest_rs);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, offset);
        code.movzx(edx, rs.cvt16());
        code.mov(rax, cast(u64) code.config.write_handler16);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stmw(Code code, u32 opcode) {
    // store regs[rs] to regs[31] to mem
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  offset   = sext_32(opcode.bits(0, 15), 16);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    int loop_ofs = 0;
    for (int i = opcode.bits(21, 25); i < 32; i++) {
        auto rs = code.get_reg(i.to_gpr);
        code.push(ra);
        code.push(rdi);
        code.enter_stack_alignment_context();

            code.mov(esi, ra);
            code.add(esi, offset + loop_ofs);
            code.mov(edx, rs);
            code.mov(rdi, cast(u64) code.config.mem_handler_context);
            code.mov(rax, cast(u64) code.config.write_handler32);
            code.call(rax);

        code.exit_stack_alignment_context();
        code.pop(rdi);
        code.pop(ra);
        code.free_register(rs);

        loop_ofs += 4;
    }

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stw(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  offset   = sext_32(opcode.bits(0, 15), 16);
    auto rs       = code.get_reg(guest_rs);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, offset);
        code.mov(edx, rs);
        code.mov(rax, cast(u64) code.config.write_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stbx(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, rb);
        code.movzx(edx, rs.cvt8());
        code.mov(rax, cast(u64) code.config.write_handler8);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_sthx(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, rb);
        code.movzx(edx, rs.cvt16());
        code.mov(rax, cast(u64) code.config.write_handler16);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stwx(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    Reg32 ra = code.allocate_register();
    if (guest_ra == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(guest_ra);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.add(esi, rb);
        code.mov(edx, rs);
        code.mov(rax, cast(u64) code.config.write_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_stwu(Code code, u32 opcode) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  offset   = sext_32(opcode.bits(0, 15), 16);

    assert(guest_ra != GuestReg.R0);

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_reg(guest_rs);

    code.mov(esi, ra);
    code.add(esi, offset);
    code.set_reg(guest_ra, esi);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(edx, rs);

        code.mov(rax, cast(u64) code.config.write_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_subfx(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    bool oe       = opcode.bit(10);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);

    code.mov(ah, 1);
    code.sahf();

    code.not(ra);
    code.adc(ra, rb);
    code.set_reg(guest_rd, ra);

    set_flags(code, false, rc, oe, ra, ra, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_subfcx(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    bool oe       = opcode.bit(10);

    auto ra = code.get_reg(guest_ra);    
    auto rb = code.get_reg(guest_rb);

    code.mov(ah, 1);
    code.sahf();

    code.not(ra);
    code.adc(ra, rb);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, rc, oe, ra, ra, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_subfex(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    bool oe       = opcode.bit(10);

    auto ra = code.get_reg(guest_ra);    
    auto rb = code.get_reg(guest_rb);

    code.mov(eax, code.get_address(GuestReg.XER));
    code.shr(eax, 21);
    code.sahf();

    code.not(ra);
    code.adc(ra, rb);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, rc, oe, ra, ra, rb, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_subfic(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);

    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  simm     = sext_32(opcode.bits(0, 15), 16);
    auto ra       = code.get_reg(guest_ra);

    code.mov(ah, 1);
    code.sahf();

    code.not(ra);
    code.adc(ra, simm);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, false, false, ra, ra, code.allocate_register(), code.allocate_register(), 0);

    return EmissionAction.CONTINUE;    
}

private EmissionAction emit_subfmex(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool rc       = opcode.bit(0);
    bool oe       = opcode.bit(10);
    auto ra       = code.get_reg(guest_ra);

    assert(opcode.bits(11, 15) == 0);

    code.not(ra);

    code.mov(eax, code.get_address(GuestReg.XER));
    code.shr(eax, 29);
    code.and(eax, 1);
    code.sub(eax, 1);

    code.add(ra, eax);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, rc, oe, ra, ra, eax, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_subfzex(Code code, u32 opcode) {
    code.reserve_register(eax);
    code.reserve_register(ecx);
    
    auto guest_rd = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    bool rc       = opcode.bit(0);
    bool oe       = opcode.bit(10);
    auto ra       = code.get_reg(guest_ra);

    assert(opcode.bits(11, 15) == 0);

    code.not(ra);

    code.mov(eax, code.get_address(GuestReg.XER));
    code.shr(eax, 21);
    code.and(eax, 1);

    code.add(ra, eax);
    code.set_reg(guest_rd, ra);

    set_flags(code, true, rc, oe, ra, ra, eax, code.allocate_register(), 0);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_sync(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_xor(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    bool rc       = opcode.bit(0);
    auto rs       = code.get_reg(guest_rs);
    auto rb       = code.get_reg(guest_rb);

    code.xor(rs, rb);
    code.set_reg(guest_ra, rs);

    set_flags(code, false, rc, false, rs, rs, rb, code.allocate_register(), 0);
    
    return EmissionAction.CONTINUE;
}

private EmissionAction emit_xori(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  uimm     = opcode.bits(0, 15);
    auto rs       = code.get_reg(guest_rs);

    code.xor(rs, uimm);
    code.set_reg(guest_ra, rs);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_xoris(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int  uimm     = opcode.bits(0, 15) << 16;
    auto rs       = code.get_reg(guest_rs);

    code.xor(rs, uimm);
    code.set_reg(guest_ra, rs);

    return EmissionAction.CONTINUE;
}

private EmissionAction emit_op_04(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp04SecondaryOpcode.PS_MR: return emit_ps_mr(code, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_13(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp13SecondaryOpcode.BCCTR: return emit_bcctr(code, opcode);
        case PrimaryOp13SecondaryOpcode.BCLR:  return emit_bclr (code, opcode);
        case PrimaryOp13SecondaryOpcode.RFI:   return emit_rfi  (code, opcode);
        case PrimaryOp13SecondaryOpcode.CRXOR: return emit_crxor(code, opcode);
        case PrimaryOp13SecondaryOpcode.ISYNC: return emit_isync(code, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_1F(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        case PrimaryOp1FSecondaryOpcode.ADD:     return emit_addx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDC:    return emit_addcx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDCO:   return emit_addcx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDE:    return emit_addex  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDEO:   return emit_addex  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDO:    return emit_addx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDME:   return emit_addmex (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDMEO:  return emit_addmex (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDZE:   return emit_addzex (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ADDZEO:  return emit_addzex (code, opcode);
        case PrimaryOp1FSecondaryOpcode.AND:     return emit_and    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ANDC:    return emit_andc   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.CNTLZW:  return emit_cntlzw (code, opcode);
        case PrimaryOp1FSecondaryOpcode.CMP:     return emit_cmp    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.CMPL:    return emit_cmpl   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DCBF:    return emit_dcbf   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DCBI:    return emit_dcbi   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DCBST:   return emit_dcbst  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DIVW:    return emit_divwx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DIVWO:   return emit_divwx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DIVWU:   return emit_divwux (code, opcode);
        case PrimaryOp1FSecondaryOpcode.DIVWUO:  return emit_divwux (code, opcode);
        case PrimaryOp1FSecondaryOpcode.EQV:     return emit_eqv    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.EXTSB:   return emit_extsb  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.EXTSH:   return emit_extsh  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.HLE:     return emit_hle    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ICBI:    return emit_icbi   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.LBZX:    return emit_lbzx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.LHZX:    return emit_lhzx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.LWZX:    return emit_lwzx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MFCR:    return emit_mfcr   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MFMSR:   return emit_mfmsr  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MFSPR:   return emit_mfspr  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MFTB:    return emit_mftb   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MTCRF:   return emit_mtcrf  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MTMSR:   return emit_mtmsr  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MTSPR:   return emit_mtspr  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MTSR:    return emit_mtsr   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MULLW:   return emit_mullwx (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MULLWO:  return emit_mullwx (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MULHW:   return emit_mulhw  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.MULHWU:  return emit_mulhwu (code, opcode);
        case PrimaryOp1FSecondaryOpcode.NAND:    return emit_nand   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.NEG:     return emit_negx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.NEGO:    return emit_negx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.NOR:     return emit_nor    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.OR:      return emit_or     (code, opcode);
        case PrimaryOp1FSecondaryOpcode.ORC:     return emit_orc    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SLW:     return emit_slw    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SRAW:    return emit_sraw   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SRAWI:   return emit_srawi  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SRW:     return emit_srw    (code, opcode);
        case PrimaryOp1FSecondaryOpcode.STBX:    return emit_stbx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.STHX:    return emit_sthx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.STWX:    return emit_stwx   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBF:    return emit_subfx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFO:   return emit_subfx  (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFC:   return emit_subfcx (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFCO:  return emit_subfcx (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFE:   return emit_subfex (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFEO:  return emit_subfex (code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFME:  return emit_subfmex(code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFMEO: return emit_subfmex(code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFZE:  return emit_subfzex(code, opcode);
        case PrimaryOp1FSecondaryOpcode.SUBFZEO: return emit_subfzex(code, opcode);
        case PrimaryOp1FSecondaryOpcode.SYNC:    return emit_sync   (code, opcode);
        case PrimaryOp1FSecondaryOpcode.XOR:     return emit_xor    (code, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_3B(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        // case PrimaryOp3BSecondaryOpcode.FADDSX:   return emit_faddsx  (code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FDIVSX:   return emit_fdivsx  (code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FMADDSX:  return emit_fmaddsx (code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FMSUBSX:  return emit_fmsubsx (code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FMULSX:   return emit_fmulsx  (code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FNMADDSX: return emit_fnmaddsx(code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FNMSUBSX: return emit_fnmsubsx(code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FRESX:    return emit_fresx   (code, opcode);
        // case PrimaryOp3BSecondaryOpcode.FSUBSX:   return emit_fsubsx  (code, opcode);

        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

private EmissionAction emit_op_3F(Code code, u32 opcode) {
    int secondary_opcode = opcode.bits(1, 10);

    switch (secondary_opcode) {
        // case PrimaryOp3FSecondaryOpcode.FABSX:  return emit_fabsx  (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FCTIWX: return emit_fctiwx (code, opcode);
        case PrimaryOp3FSecondaryOpcode.FMR:    return emit_fmr    (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNABSX: return emit_fnabsx (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNEGX:  return emit_fnegx  (code, opcode);
        case PrimaryOp3FSecondaryOpcode.MFTSB1: return emit_mftsb1 (code, opcode);
        case PrimaryOp3FSecondaryOpcode.MTFSF:  return emit_mtfsf  (code, opcode);
        default: break;
    }

    secondary_opcode = opcode.bits(1, 5);

    switch (secondary_opcode) {
        // case PrimaryOp3FSecondaryOpcode.FADDX:   return emit_faddx  (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FDIVX:   return emit_fdivx  (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMADDX:  return emit_fmaddx (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMSUBX:  return emit_fmsubx (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FMULX:   return emit_fmulx  (code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNMADDX: return emit_fnmaddx(code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FNMSUBX: return emit_fnmsubx(code, opcode);
        // case PrimaryOp3FSecondaryOpcode.FSEL:    return emit_fsel   (code, opcode);
        default: unimplemented_opcode(opcode); return EmissionAction.STOP;
    }
}

public EmissionAction disassemble(Code code, u32 opcode) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:   return emit_addi  (code, opcode);
        case PrimaryOpcode.ADDIC:  return emit_addic (code, opcode);
        case PrimaryOpcode.ADDIC_: return emit_addic_(code, opcode);
        case PrimaryOpcode.ADDIS:  return emit_addis (code, opcode);
        case PrimaryOpcode.ANDI:   return emit_andi  (code, opcode);
        case PrimaryOpcode.ANDIS:  return emit_andis (code, opcode);
        case PrimaryOpcode.B:      return emit_b     (code, opcode);
        case PrimaryOpcode.BC:     return emit_bc    (code, opcode);
        case PrimaryOpcode.CMPLI:  return emit_cmpli (code, opcode);
        case PrimaryOpcode.CMPI:   return emit_cmpi  (code, opcode);
        case PrimaryOpcode.LBZ:    return emit_lbz   (code, opcode);
        case PrimaryOpcode.LBZU:   return emit_lbzu  (code, opcode);
        case PrimaryOpcode.LFD:    return emit_lfd   (code, opcode);
        case PrimaryOpcode.LHA:    return emit_lha   (code, opcode);
        case PrimaryOpcode.LHZ:    return emit_lhz   (code, opcode);
        case PrimaryOpcode.LHZU:   return emit_lhzu  (code, opcode);
        case PrimaryOpcode.LMW:    return emit_lmw   (code, opcode);
        case PrimaryOpcode.LWZ:    return emit_lwz   (code, opcode);
        case PrimaryOpcode.LWZU:   return emit_lwzu  (code, opcode);
        case PrimaryOpcode.MULLI:  return emit_mulli (code, opcode);
        case PrimaryOpcode.ORI:    return emit_ori   (code, opcode);
        case PrimaryOpcode.ORIS:   return emit_oris  (code, opcode);
        case PrimaryOpcode.PSQ_L:  return emit_psq_l (code, opcode);
        case PrimaryOpcode.RLWIMI: return emit_rlwimi(code, opcode);
        case PrimaryOpcode.RLWINM: return emit_rlwinm(code, opcode);
        case PrimaryOpcode.RLWNM:  return emit_rlwnm (code, opcode);
        case PrimaryOpcode.SC:     return emit_sc    (code, opcode);
        case PrimaryOpcode.STB:    return emit_stb   (code, opcode);
        case PrimaryOpcode.STBU:   return emit_stbu  (code, opcode);
        case PrimaryOpcode.STH:    return emit_sth   (code, opcode);
        case PrimaryOpcode.STMW:   return emit_stmw  (code, opcode);
        case PrimaryOpcode.STW:    return emit_stw   (code, opcode);
        case PrimaryOpcode.STWU:   return emit_stwu  (code, opcode);
        case PrimaryOpcode.SUBFIC: return emit_subfic(code, opcode);
        case PrimaryOpcode.XORI:   return emit_xori  (code, opcode);
        case PrimaryOpcode.XORIS:  return emit_xoris (code, opcode);

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
    
    import capstone;

    // auto cs = create(Arch.ppc, ModeFlags(Mode.bit32));
    // auto opcode = mem.read_be_u32(address);
    // log_jit("Disassembling opcode 0x%08x", address);
    // auto res = cs.disasm((cast(ubyte*) &opcode)[0 .. 4], 0);
    // foreach (instr; res) {
    //     log_jit("[GUEST] 0x%08x | %s\t\t%s", address, instr.mnemonic, instr.opStr);
    // }
    // log_jit("Opcode: 0x%08x", opcode);

    while (num_opcodes_processed < MAX_GUEST_OPCODES_PER_RECIPE) {
        EmissionAction action = disassemble(code, mem.read_be_u32(address));

        num_opcodes_processed++;
        if (num_opcodes_processed == MAX_GUEST_OPCODES_PER_RECIPE && action != EmissionAction.STOP) {
            auto pc = code.get_reg(GuestReg.PC);
            code.add(pc, 4);
            code.set_reg(GuestReg.PC, pc);
        }

        if (action == EmissionAction.STOP) {
            break;
        }

        code.free_all_registers();
    }
    
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
