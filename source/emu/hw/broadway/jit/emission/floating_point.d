module emu.hw.broadway.jit.emission.floating_point;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.emission_action;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.flags;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.helpers;
import gallinule.x86;
import util.bitop;
import util.log;
import util.number;

EmissionAction emit_fcmpo(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto crfd = opcode.bits(23, 25);

    assert(opcode.bits(21, 22) == 0);

    auto ra = code.get_fpr(guest_ra);
    auto rb = code.get_fpr(guest_rb);

    code.movq(xmm0, ra);
    code.movq(xmm1, rb);

    code.comisd(xmm0, xmm1);
    emit_fp_flags_helper(code, crfd, ra.cvt32());

    return EmissionAction.Continue;
}

EmissionAction emit_fcmpu(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto crfd = opcode.bits(23, 25);

    assert(opcode.bits(21, 22) == 0);

    auto ra = code.get_fpr(guest_ra);
    auto rb = code.get_fpr(guest_rb);

    code.movq(xmm0, ra);
    code.movq(xmm1, rb);
    code.ucomisd(xmm0, xmm1);
    emit_fp_flags_helper(code, crfd, ra.cvt32());

    return EmissionAction.Continue;
}

EmissionAction emit_fmr(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rs = opcode.bits(11, 15).to_fpr;

    auto rs = code.get_fpr(guest_rs);
    code.set_fpr(guest_rd, rs);

    return EmissionAction.Continue;
}

EmissionAction emit_lfd(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    if (guest_ra == GuestReg.R0) {
        code.mov(ra, imm);
    } else {
        code.add(ra, imm);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_fpr(guest_rd, rax);

    return EmissionAction.Continue;
}

EmissionAction emit_lfdu(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    code.add(ra, imm);
    code.set_reg(guest_ra, ra);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_fpr(guest_rd, rax);

    return EmissionAction.Continue;
}

EmissionAction emit_lfdux(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);
    code.add(ra, rb);
    code.set_reg(guest_ra, ra);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_fpr(guest_rd, rax);

    return EmissionAction.Continue;
}

EmissionAction emit_stfdx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rs = opcode.bits(21, 25).to_fpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_fpr(guest_rs);
    auto rb = code.get_reg(guest_rb);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.mov(rdx, rs);

        code.mov(rax, cast(u64) code.config.write_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.Continue;
}

EmissionAction emit_stfiwx(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_fpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_fpr(guest_rs);
    auto rb = code.get_reg(guest_rb);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.mov(edx, rs.cvt32());

        code.mov(rax, cast(u64) code.config.write_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.Continue;
}

EmissionAction emit_stfd(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rs = opcode.bits(21, 25).to_fpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_fpr(guest_rs);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, imm);
    } else {
        code.add(ra, imm);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.mov(rdx, rs);

        code.mov(rax, cast(u64) code.config.write_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.Continue;
}

EmissionAction emit_stfdu(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rs = opcode.bits(21, 25).to_fpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_fpr(guest_rs);

    code.add(ra, imm);
    code.set_reg(guest_ra, ra);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.mov(rdx, rs);

        code.mov(rax, cast(u64) code.config.write_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.Continue;
}

EmissionAction emit_stfsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rs = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    assert(opcode.bit(0) == 0);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);
    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    code.get_ps(guest_rs, xmm0);
    code.cvtsd2ss(xmm0, xmm0);
    code.movd(edx, xmm0);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.write_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.Continue;
}

EmissionAction emit_lfsux(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_ps;

    auto ra = code.get_reg(guest_ra);
    code.add(ra, code.get_reg(guest_rb));
    code.set_reg(guest_ra, ra);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.movq(xmm0, rax);
    code.cvtss2sd(xmm0, xmm0);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_mftsb1(Code code, u32 opcode) {
    bool rc = opcode.bit(0);

    // TODO: ist his supposed to be backwards indexed?
    int crbD = opcode.bits(21, 25);

    // what?
    assert(!rc);

    assert(opcode.bits(11, 20) == 0);

    code.or(code.get_address(GuestReg.FPSCR), 1 << crbD);

    return EmissionAction.Continue;
}

EmissionAction emit_lfsu(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_ps;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    code.add(ra, imm);
    code.set_reg(guest_ra, ra);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.movq(xmm0, rax);
    code.cvtss2sd(xmm0, xmm0);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_lfs(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_ps;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    if (guest_ra == GuestReg.R0) {
        code.mov(ra, imm);
    } else {
        code.add(ra, imm);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.movq(xmm0, rax);
    code.cvtss2sd(xmm0, xmm0);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_stfs(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rs = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int imm = sext_32(opcode.bits(0, 15), 16);

    R32 ra;
    if (guest_ra == GuestReg.R0) {
        ra = code.allocate_register();
        code.mov(ra, imm);
    } else {
        ra = code.get_reg(guest_ra);
        code.add(ra, imm);
    }

    code.get_ps(guest_rs, xmm0);
    code.cvtsd2ss(xmm0, xmm0);
    code.movd(edx, xmm0);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.write_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);
    
    return EmissionAction.Continue;
}

EmissionAction emit_fsel(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;

    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    auto smaller = code.fresh_label();
    auto end = code.fresh_label();

    code.xorpd(xmm4, xmm4);
    code.ucomisd(xmm0, xmm4);
    code.jb(smaller);
    
    code.movq(xmm0, xmm2);
    code.jmp(end);

code.label(smaller);
    code.movq(xmm0, xmm1);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fmulsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rc, xmm1);

    auto paired_single = code.fresh_label();
    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jnz(paired_single);

    code.mulsd(xmm0, xmm1);
    code.jmp(end);

code.label(paired_single);
    code.mulsd(xmm0, xmm1);
    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fdivsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.divsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fsub(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.subsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fresx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    auto paired_single = code.fresh_label();
    auto end = code.fresh_label();

    code.get_ps(guest_rb, xmm0);
    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jnz(paired_single);

    code.cvtsd2ss(xmm0, xmm0);
    code.rcpss(xmm0, xmm0);
    code.cvtss2sd(xmm0, xmm0);
    code.jmp(end);

code.label(paired_single);
    code.cvtsd2ss(xmm0, xmm0);
    code.rcpss(xmm0, xmm0);
    code.cvtss2sd(xmm0, xmm0);
    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_faddsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.addsd(xmm0, xmm1);
    code.vpbroadcastq(xmm0, xmm0);

    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fsubsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_ra = opcode.bits(11, 15).to_ps;
    auto guest_rb = opcode.bits(16, 20).to_ps;
    auto guest_rd = opcode.bits(21, 25).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_rb, xmm0);
    code.get_ps(guest_ra, xmm1);

    code.subsd(xmm0, xmm1);
    code.vpbroadcastq(xmm0, xmm0);

    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fctiwzx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    auto rb = code.get_fpr(guest_rb);

    code.movq(xmm0, rb);
    code.cvtsd2si(rb, xmm0);

    code.set_fpr(guest_rd, rb);

    return EmissionAction.Continue;
}

EmissionAction emit_frspx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    // what in the holy fuck

    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    auto rb = code.get_fpr(guest_rb);

    code.movq(xmm0, rb);
    code.cvtsd2ss(xmm0, xmm0);
    code.cvtss2sd(xmm0, xmm0);
    code.movq(rb, xmm0);
    code.set_fpr(guest_rd, rb);

    return EmissionAction.Continue;
}

EmissionAction emit_lfsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    assert(opcode.bit(0) == 0);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);
    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler32);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.movq(xmm0, rax);
    code.cvtss2sd(xmm0, xmm0);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fabsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(opcode.bits(16, 20) == 0);
    assert(rc == 0);

    auto tmp = code.allocate_register();
    auto tmp2 = code.allocate_register();

    code.get_ps(guest_rb, xmm0);
    code.movq(tmp.cvt64(), xmm0);
    code.mov(tmp2.cvt64(), ~0x80000000_00000000);
    code.and(tmp.cvt64(), tmp2.cvt64());
    code.movq(xmm0, tmp.cvt64());
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_lfdx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rb = opcode.bits(11, 15).to_gpr;
    assert(opcode.bit(0) == 0);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);
    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);

        code.mov(rax, cast(u64) code.config.read_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    code.set_fpr(guest_rd, rax);

    return EmissionAction.Continue;
}

EmissionAction emit_faddx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.addsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fmsubx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    code.mulsd(xmm0, xmm2);
    code.subsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fmsubsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    auto paired_single = code.fresh_label();
    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jnz(paired_single);

    code.mulsd(xmm0, xmm2);
    code.subsd(xmm0, xmm1);
    code.jmp(end);

code.label(paired_single);
    code.mulsd(xmm0, xmm2);
    code.subsd(xmm0, xmm1);
    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_frsqrtex(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_rb, xmm0);
    code.cvtsd2ss(xmm0, xmm0);
    code.rsqrtss(xmm0, xmm0);
    code.cvtss2sd(xmm0, xmm0);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fdivx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rd = opcode.bits(21, 25).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_ra, xmm0);

    code.divsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fmulx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(6,  10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.mulsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fnegx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(opcode.bits(16, 20) == 0);
    assert(rc == 0);

    auto tmp = code.allocate_register();
    auto tmp2 = code.allocate_register();

    code.get_ps(guest_rb, xmm0);
    code.movq(tmp.cvt64(), xmm0);
    code.mov(tmp2.cvt64(), 0x80000000_00000000);
    code.xor(tmp.cvt64(), tmp2.cvt64());
    code.movq(xmm0, tmp.cvt64());
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fnmaddsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    auto tmp = code.allocate_register();
    auto tmp2 = code.allocate_register();

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    code.mulsd(xmm0, xmm2);
    code.addsd(xmm0, xmm1);
    code.movq(tmp.cvt64(), xmm0);
    code.mov(tmp2.cvt64(), 0x80000000_00000000);
    code.xor(tmp.cvt64(), tmp2.cvt64());
    code.movq(xmm0, tmp.cvt64);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fnmsubsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    auto tmp = code.allocate_register();
    auto tmp2 = code.allocate_register();

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    code.mulsd(xmm0, xmm2);
    code.subsd(xmm0, xmm1);
    code.movq(tmp.cvt64(), xmm0);
    code.mov(tmp2.cvt64(), 0x80000000_00000000);
    code.xor(tmp.cvt64(), tmp2.cvt64());
    code.movq(xmm0, tmp.cvt64);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_fmaddsx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    code.mulsd(xmm0, xmm2);
    code.addsd(xmm0, xmm1);

    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);

    code.vpbroadcastq(xmm0, xmm0);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_mffs(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);
    
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    bool rc = opcode.bit(0);

    assert(opcode.bits(11, 20) == 0);
    assert(rc == 0);

    auto tmp = code.allocate_register();
    code.mov(code.get_address(GuestReg.FPSCR), tmp);
    code.set_fpr(guest_rd, tmp.cvt64);

    return EmissionAction.Continue;
}