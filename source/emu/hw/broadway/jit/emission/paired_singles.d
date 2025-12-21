module emu.hw.broadway.jit.emission.paired_singles;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.emission_action;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.flags;
import emu.hw.broadway.jit.emission.helpers;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.memory.strategy.memstrategy;
import gallinule.x86;
import util.bitop;
import util.log;
import util.number;

EmissionAction emit_psq_st_generic(Code code, R32 address, GuestReg guest_rs, int i, bool w) {
    code.reserve_register(eax);

    code.get_ps(guest_rs, xmm0);

    auto gqr = code.get_reg(cast(GuestReg) (GuestReg.GQR0 + i));
    if (w) {
        code.cvtsd2ss(xmm0, xmm0);
        quantize(code, xmm0, address, gqr, code.allocate_register(), code.allocate_register(), xmm1, false);
    } else {
        code.cvtsd2ss(xmm1, xmm0);
        quantize(code, xmm1, address, gqr, code.allocate_register(), code.allocate_register(), xmm2, true);
        
        code.get_ps(guest_rs, xmm0);
        code.shufpd(xmm0, xmm0, 0b00000001);
        code.cvtsd2ss(xmm0, xmm0);
        quantize(code, xmm0, address, gqr, code.allocate_register(), code.allocate_register(), xmm1, false);
    }

    return EmissionAction.Continue;
}

EmissionAction emit_psq_st(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse_or_lsqe(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;    
    auto guest_rs = opcode.bits(21, 25).to_ps;
    bool w = opcode.bit(15);
    int i = opcode.bits(12, 14);
    int d = sext_32(opcode.bits(0, 11), 12);

    auto address = calculate_effective_address_displacement(code, guest_ra, d);

    return emit_psq_st_generic(code, address, guest_rs, i, w);
}

EmissionAction emit_psq_stx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse_or_lsqe(code);

    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;    
    auto guest_rs = opcode.bits(21, 25).to_ps;
    
    bool w = opcode.bit(10);
    int i = opcode.bits(7, 9);

    auto ra = code.get_reg(guest_ra);
    auto rb = code.get_reg(guest_rb);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    return emit_psq_st_generic(code, ra, guest_rs, i, w);
}

EmissionAction emit_psq_stu(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse_or_lsqe(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;    
    auto guest_rs = opcode.bits(21, 25).to_ps;
    bool w = opcode.bit(15);
    int i = opcode.bits(12, 14);
    int d = sext_32(opcode.bits(0, 11), 12);

    auto ra = code.get_reg(guest_ra);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, d);
    } else {
        code.add(ra, d);
    }

    code.set_reg(guest_ra, ra);

    return emit_psq_st_generic(code, ra, guest_rs, i, w);
}

EmissionAction emit_psq_l_generic(Code code, R64 dest, GuestReg guest_rd, R32 address, int i, bool w) {
    code.reserve_register(eax);

    auto gqr = code.get_reg(cast(GuestReg) (GuestReg.GQR0 + i));
    
    if (w) {
        dequantize(code, xmm0, address, gqr, code.allocate_register(), code.allocate_register(), xmm1, false);
        code.cvtss2sd(xmm0, xmm0);
        code.mov(dest, 0x3ff0_0000_0000_0000UL);
        code.movq(xmm1, dest);
        code.punpcklqdq(xmm0, xmm1);
        code.set_ps(guest_rd, xmm0);
    } else {
        dequantize(code, xmm0, address, gqr, code.allocate_register(), code.allocate_register(), xmm2, true);
        dequantize(code, xmm1, address, gqr, code.allocate_register(), code.allocate_register(), xmm2, false);
        code.cvtss2sd(xmm0, xmm0);
        code.cvtss2sd(xmm1, xmm1);
        code.punpcklqdq(xmm0, xmm1);
        code.set_ps(guest_rd, xmm0);
    }

    return EmissionAction.Continue;
}

EmissionAction emit_psq_lu(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse_or_lsqe(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    bool w = opcode.bit(15);
    int i = opcode.bits(12, 14);
    int d = sext_32(opcode.bits(0, 11), 12);

    auto ra = code.get_reg(guest_ra);
    auto rd = code.get_fpr(guest_rd);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, d);
    } else {
        code.add(ra, d);
    }

    code.set_reg(guest_ra, ra);

    return code.emit_psq_l_generic(rd, guest_rd, ra, i, w);
}

EmissionAction emit_psq_l(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse_or_lsqe(code);

    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    bool w = opcode.bit(15);
    int i = opcode.bits(12, 14);
    int d = sext_32(opcode.bits(0, 11), 12);

    auto ra = code.get_reg(guest_ra);
    auto rd = code.get_fpr(guest_rd);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, d);
    } else {
        code.add(ra, d);
    }

    return code.emit_psq_l_generic(rd, guest_rd, ra, i, w);
}

EmissionAction emit_psq_lx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse_or_lsqe(code);

    auto guest_rb = opcode.bits(11, 15).to_gpr;
    auto guest_ra = opcode.bits(16, 20).to_gpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    bool w = opcode.bit(10);
    int i = opcode.bits(7, 9);

    auto rb = code.get_reg(guest_rb);
    auto ra = code.get_reg(guest_ra);
    auto rd = code.get_fpr(guest_rd);

    if (guest_ra == GuestReg.R0) {
        code.mov(ra, rb);
    } else {
        code.add(ra, rb);
    }

    return code.emit_psq_l_generic(rd, guest_rd, ra, i, w);
}

EmissionAction emit_ps_abs(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    auto tmp = code.allocate_register();
    code.mov(tmp.cvt64(), ~0x80000000_00000000);
    code.movq(xmm0, tmp.cvt64());
    code.vpbroadcastq(xmm0, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.andpd(xmm1, xmm0);
    code.set_ps(guest_rd, xmm1);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_add(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.addpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_msubx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.mulpd(xmm0, xmm2);
    code.subpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_subx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.subpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_maddx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.mulpd(xmm0, xmm2);
    code.addpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_sel(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6, 10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);

    code.xorpd(xmm3, xmm3);
    code.cmppd(xmm0, xmm3, 0xD);
    code.pandn(xmm1, xmm0);
    code.pand(xmm2, xmm0);
    code.por(xmm1, xmm2);

    code.set_ps(guest_rd, xmm1);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_sum0(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rc = opcode.bits(6, 10).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.shufpd(xmm1, xmm1, 1);  // xmm1 = [b0, b1]
    code.addpd(xmm0, xmm1);      // xmm0 = [a1 + b0, a0 + b1]
    code.blendpd(xmm0, xmm2, 2); // xmm2 = [c1, a0 + b1]
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_sum1(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    auto guest_rc = opcode.bits(6, 10).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.shufpd(xmm0, xmm0, 1);  // xmm0 = [a0, a1]
    code.addpd(xmm0, xmm1);      // xmm0 = [a0 + b1, a1 + b0]
    code.blendpd(xmm0, xmm2, 1); // xmm2 = [a0 + b1, c0]
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_mulx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.mulpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_cmpo0(Code code, u32 opcode) {
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

EmissionAction emit_ps_cmpu0(Code code, u32 opcode) {
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

EmissionAction emit_ps_cmpu1(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto crfd = opcode.bits(23, 25);

    assert(opcode.bits(21, 22) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);

    code.shufpd(xmm0, xmm0, 1);
    code.shufpd(xmm1, xmm1, 1);

    code.ucomisd(xmm0, xmm1);
    emit_fp_flags_helper(code, crfd, code.allocate_register().cvt32());

    return EmissionAction.Continue;
}

EmissionAction emit_ps_madds0x(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.vpbroadcastq(xmm2, xmm2);
    code.mulpd(xmm0, xmm2);
    code.addpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_madds1x(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.shufpd(xmm2, xmm2, 3);
    code.mulpd(xmm0, xmm2);
    code.addpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_absx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    auto tmp = code.allocate_register();

    code.get_ps(guest_ra, xmm0);
    code.mov(tmp.cvt64(), 0x7FFF_FFFF_FFFF_FFFFUL);
    code.movq(xmm1, tmp.cvt64());
    code.vpbroadcastq(xmm1, xmm1);
    code.andpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_negx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(11, 15).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    auto tmp = code.allocate_register();
    auto tmp2 = code.allocate_register();

    code.get_ps(guest_ra, xmm0);
    code.mov(tmp.cvt64(), 0x8000_0000_0000_0000UL);
    code.movq(xmm1, tmp.cvt64());
    code.vpbroadcastq(xmm1, xmm1);
    code.xorpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_mr(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    assert(opcode.bits(16, 20) == 0);

    code.get_ps(guest_rb, xmm0);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_merge11(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.shufpd(xmm0, xmm1, 0b0011);

    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_merge01(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.shufpd(xmm0, xmm1, 0b0010);

    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_merge00(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.shufpd(xmm0, xmm1, 0b0000);

    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_merge10(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.shufpd(xmm0, xmm1, 0b0001);

    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_div(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rb = opcode.bits(11, 15).to_ps;
    auto guest_rd = opcode.bits(21, 25).to_ps;
    assert(opcode.bit(0) == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.divpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_muls0(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rc, xmm1);

    code.vpbroadcastq(xmm1, xmm1);
    code.mulpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_muls1(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_rd = opcode.bits(21, 25).to_ps;
    auto guest_ra = opcode.bits(16, 20).to_ps;
    auto guest_rc = opcode.bits(6, 10).to_ps;
    bool rc = opcode.bit(0);
    assert(rc == 0);

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rc, xmm1);

    code.shufpd(xmm1, xmm1, 3);
    code.mulpd(xmm0, xmm1);
    code.set_ps(guest_rd, xmm0);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_nmaddx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    auto tmp = code.allocate_register();

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.mulpd(xmm0, xmm2);
    code.addpd(xmm0, xmm1);
    code.mov(tmp.cvt64(), 0x8000_0000_0000_0000UL);
    code.movq(xmm1, tmp.cvt64());
    code.vpbroadcastq(xmm1, xmm1);
    code.xorpd(xmm1, xmm0);
    code.set_ps(guest_rd, xmm1);

    return EmissionAction.Continue;
}

EmissionAction emit_ps_nmsubx(Code code, u32 opcode) {
    check_fp_enabled_or_jump(code);

    abort_if_no_pse(code);

    auto guest_ra = opcode.bits(16, 20).to_fpr;
    auto guest_rb = opcode.bits(11, 15).to_fpr;
    auto guest_rc = opcode.bits(6,  10).to_fpr;
    auto guest_rd = opcode.bits(21, 25).to_fpr;
    assert(opcode.bit(0) == 0);

    auto tmp = code.allocate_register();

    code.get_ps(guest_ra, xmm0);
    code.get_ps(guest_rb, xmm1);
    code.get_ps(guest_rc, xmm2);
    code.mulpd(xmm0, xmm2);
    code.subpd(xmm0, xmm1);
    code.mov(tmp.cvt64(), 0x8000_0000_0000_0000UL);
    code.movq(xmm1, tmp.cvt64());
    code.vpbroadcastq(xmm1, xmm1);
    code.xorpd(xmm1, xmm0);
    code.set_ps(guest_rd, xmm1);

    return EmissionAction.Continue;
}

void dequantize(Code code, XMM dest, R32 address, R32 gqr, R32 tmp1, R32 tmp2, XMM tmp_xmm, bool increment_address) {
    code.mov(tmp1, gqr);
    code.mov(tmp2, gqr);
    code.and(tmp1, 0b111111 << 24);
    code.shr(tmp1, 24);
    code.and(tmp2, 0b111 << 16);
    code.shr(tmp2, 16);

    auto dequantize_float = code.fresh_label();
    auto dequantize_u8 = code.fresh_label();
    auto dequantize_u16 = code.fresh_label();
    auto dequantize_s8 = code.fresh_label();
    auto dequantize_s16 = code.fresh_label();
    auto end = code.fresh_label();

    code.cmp(tmp2, 0);
    code.je(dequantize_float);
    
    // materialize 2^(tmp1)
    code.shl(tmp1, 26);
    code.sar(tmp1, 26);
    code.add(tmp1, 127);
    code.shl(tmp1, 23); 

    code.movd(tmp_xmm, tmp1);
    
    code.cmp(tmp2, 4);
    code.je(dequantize_u8);
    code.cmp(tmp2, 5);
    code.je(dequantize_u16);
    code.cmp(tmp2, 6);
    code.je(dequantize_s8);
    code.cmp(tmp2, 7);
    code.je(dequantize_s16);
    abort(code);

code.label(dequantize_float);
    load_32(code, address, tmp1);
    code.movd(dest, tmp1);
    if (increment_address) code.add(address, 4);
    code.jmp(end);

code.label(dequantize_u8);
    load_8(code, address, tmp1);
    code.movzx(tmp1, tmp1.cvt8());
    code.cvtsi2ss(dest, tmp1);
    code.divss(dest, tmp_xmm);
    if (increment_address) code.add(address, 1);
    code.jmp(end);

code.label(dequantize_u16);
    load_16(code, address, tmp1);
    code.movzx(tmp1, tmp1.cvt16());
    code.cvtsi2ss(dest, tmp1);
    code.divss(dest, tmp_xmm);
    if (increment_address) code.add(address, 2);
    code.jmp(end);

code.label(dequantize_s8);
    load_8(code, address, tmp1);
    code.movsx(tmp1, tmp1.cvt8());
    code.cvtsi2ss(dest, tmp1);
    code.divss(dest, tmp_xmm);
    if (increment_address) code.add(address, 1);
    code.jmp(end);

code.label(dequantize_s16);
    load_16(code, address, tmp1);
    code.movsx(tmp1, tmp1.cvt16());
    code.cvtsi2ss(dest, tmp1);
    code.divss(dest, tmp_xmm);
    if (increment_address) code.add(address, 2);

code.label(end);
}

void quantize(Code code, XMM src, R32 address, R32 gqr, R32 tmp1, R32 tmp2, XMM tmp_xmm, bool increment_address) {
    code.mov(tmp1, gqr);
    code.mov(tmp2, gqr);
    code.and(tmp1, 0b111111 << 8);
    code.shr(tmp1, 8);
    code.and(tmp2, 0b111 << 0);

    auto quantize_float = code.fresh_label();
    auto quantize_u8 = code.fresh_label();
    auto quantize_u16 = code.fresh_label();
    auto quantize_s8 = code.fresh_label();
    auto quantize_s16 = code.fresh_label();
    auto end = code.fresh_label();

    code.cmp(tmp2, 0);
    code.je(quantize_float);
    
    // materialize 2^(tmp1)
    code.shl(tmp1, 26);
    code.sar(tmp1, 26);
    code.add(tmp1, 127);
    code.shl(tmp1, 23); 

    code.movd(tmp_xmm, tmp1);
    code.mulss(tmp_xmm, src);
    code.roundsd(tmp_xmm, tmp_xmm, 3);
    code.cvtss2si(tmp1, tmp_xmm);

    code.cmp(tmp2, 4);
    code.je(quantize_u8);
    code.cmp(tmp2, 5);
    code.je(quantize_u16);
    code.cmp(tmp2, 6);
    code.je(quantize_s8);
    code.cmp(tmp2, 7);
    code.je(quantize_s16);
    abort(code);

code.label(quantize_float);
    code.movd(tmp2, src);
    store_32(code, address, tmp2);
    if (increment_address) code.add(address, 4);
    code.jmp(end);

code.label(quantize_u8);
    code.cmp(tmp1, cast(u32) 0x000000FF);
    code.mov(tmp2, cast(u8) 255);
    code.cmovg(tmp1, tmp2);
    code.cmp(tmp1, 0);
    code.mov(tmp2, 0);
    code.cmovl(tmp1, tmp2);
    store_8(code, address, tmp1);
    if (increment_address) code.add(address, 1);
    code.jmp(end);

code.label(quantize_u16);
    code.cmp(tmp1, cast(u16) 65535);
    code.mov(tmp2, cast(u16) 65535);
    code.cmovg(tmp1, tmp2);
    code.cmp(tmp1, 0);
    code.mov(tmp2, 0);
    code.cmovl(tmp1, tmp2);
    store_16(code, address, tmp1);
    if (increment_address) code.add(address, 2);
    code.jmp(end);

code.label(quantize_s8);
    code.cmp(tmp1, 127);
    code.mov(tmp2, 127);
    code.cmovg(tmp1, tmp2);
    code.cmp(tmp1, -128);
    code.mov(tmp2, -128);
    code.cmovl(tmp1, tmp2);
    store_8(code, address, tmp1);
    if (increment_address) code.add(address, 1);
    code.jmp(end);

code.label(quantize_s16);
    code.cmp(tmp1, 32767);
    code.mov(tmp2, 32767);
    code.cmovg(tmp1, tmp2);
    code.cmp(tmp1, -32768);
    code.mov(tmp2, -32768);
    code.cmovl(tmp1, tmp2);
    store_16(code, address, tmp1);
    if (increment_address) code.add(address, 2);

code.label(end);
}

void store_32(Code code, R32 address, R32 value) {
    raw_write32(code, address, value);
}

void store_16(Code code, R32 address, R32 value) {
    raw_write16(code, address, value);
}

void store_8(Code code, R32 address, R32 value) {
    raw_write8(code, address, value);
}

void load_32(Code code, R32 address, R32 dest) {
    raw_read32(code, address, dest);
}

void load_16(Code code, R32 address, R32 dest) {
    raw_read16(code, address, dest);
}

void load_8(Code code, R32 address, R32 dest) {
    raw_read8(code, address, dest);
}

void abort_if_no_pse_or_lsqe(Code code) {
    auto noabort = code.fresh_label();
    
    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 0b1010 << 28);
    code.jnz(noabort);
    abort(code);
    code.label(noabort);
}

void abort_if_no_pse(Code code) {
    auto noabort = code.fresh_label();
    
    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 0b0010 << 28);
    code.jnz(noabort);
    abort(code);
    code.label(noabort);
}