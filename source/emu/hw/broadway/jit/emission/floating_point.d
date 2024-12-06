module emu.hw.broadway.jit.emission.floating_point;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.flags;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.helpers;
import gallinule.x86;
import util.bitop;
import util.log;
import util.number;

EmissionAction emit_fcmpo(Code code, u32 opcode) {
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

    return EmissionAction.CONTINUE;
}

EmissionAction emit_fcmpu(Code code, u32 opcode) {
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

    return EmissionAction.CONTINUE;
}

EmissionAction emit_fmr(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rs = opcode.bits(11, 15).to_fpr;

    auto rs = code.get_fpr(guest_rs);
    code.set_fpr(guest_rd, rs);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_lfd(Code code, u32 opcode) {
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

    return EmissionAction.CONTINUE;
}

EmissionAction emit_stfd(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(21, 25).to_fpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    int imm = sext_32(opcode.bits(0, 15), 16);

    auto ra = code.get_reg(guest_ra);
    auto rs = code.get_fpr(guest_rs);

    code.add(ra, imm);

    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        code.mov(esi, ra);
        code.mov(rdx, rs);

        code.mov(rax, cast(u64) code.config.write_handler64);
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_stfdu(Code code, u32 opcode) {
    auto guest_rs = opcode.bits(16, 20).to_fpr;
    auto guest_ra = opcode.bits(11, 15).to_gpr;
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

    return EmissionAction.CONTINUE;
}

EmissionAction emit_mftsb1(Code code, u32 opcode) {
    bool rc = opcode.bit(0);

    // TODO: ist his supposed to be backwards indexed?
    int crbD = opcode.bits(21, 25);

    // what?
    assert(!rc);

    assert(opcode.bits(11, 20) == 0);

    code.or(code.get_address(GuestReg.FPSCR), 1 << crbD);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_lfs(Code code, u32 opcode) {
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

    return EmissionAction.CONTINUE;
}

EmissionAction emit_stfs(Code code, u32 opcode) {
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
    
    return EmissionAction.CONTINUE;
}

EmissionAction emit_fmulsx(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(16, 20).to_ps;
    auto guest_ra = opcode.bits(11, 15).to_ps;
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
    code.mulpd(xmm0, xmm1);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_fdivsx(Code code, u32 opcode) {
    auto guest_ra = opcode.bits(21, 25).to_ps;
    auto guest_rb = opcode.bits(16, 20).to_ps;
    auto guest_rd = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.divsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_fsub(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.subsd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_faddsx(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    auto paired_single = code.fresh_label();
    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jnz(paired_single);

    code.addsd(xmm0, xmm1);
    code.jmp(end);

code.label(paired_single);
    code.addpd(xmm0, xmm1);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_fsubsx(Code code, u32 opcode) {
    auto guest_ra = opcode.bits(11, 15).to_ps;
    auto guest_rb = opcode.bits(16, 20).to_ps;
    auto guest_rd = opcode.bits(21, 25).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_rb, xmm0);
    code.get_ps(guest_ra, xmm1);

    auto paired_single = code.fresh_label();
    auto end = code.fresh_label();

    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jnz(paired_single);

    code.subsd(xmm0, xmm1);
    code.jmp(end);

code.label(paired_single);
    code.subpd(xmm0, xmm1);

code.label(end);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_fctiwzx(Code code, u32 opcode) {
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    auto rb = code.get_fpr(guest_rb);

    code.movq(xmm0, rb);
    code.cvtsd2si(rb, xmm0);
    code.set_fpr(guest_rd, rb);

    return EmissionAction.CONTINUE;
}

EmissionAction emit_frspx(Code code, u32 opcode) {
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

    return EmissionAction.CONTINUE;
}