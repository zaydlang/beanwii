module emu.hw.dsp.jit.emission.emit;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.emission.flags;
import emu.hw.dsp.jit.emission.helpers;
import emu.hw.dsp.jit.jit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import gallinule.x86;
import util.bitop;
import util.number;
import util.log;
import std.conv;
import std.meta;
import std.traits;
import std.uni;

struct DspEmissionResult {
    u32 instruction_count;
}

DspEmissionResult emit_dsp_block(DspCode code, DspMemory dsp_mem, u16 pc) {
    u16 current_instruction = dsp_mem.read(pc);
    u16 next_instruction    = dsp_mem.read(cast(u16) (pc + 1));
    DspInstruction dsp_instruction = decode_instruction(current_instruction, next_instruction);

    DspJitResult result = emit_instruction(code, dsp_instruction);
    
    if (result.type == DspJitResultType.IfCc) {
        u16 next_next_instruction = dsp_mem.read(cast(u16) (pc + 2));
        DspInstruction next_dsp_instruction = decode_instruction(next_instruction, next_next_instruction);
        ulong size_of_next_instruction = next_dsp_instruction.size / 16;

        code.not(result.condition);
        code.and(result.condition, 1);
        // if (size_of_next_instruction == 1) {
            code.add(result.condition, 1);
            code.add(code.get_pc_addr(), result.condition.cvt16());
        // } else {
            // code.sal(result.condition, 1);
            // code.or(result.condition, 1);
            // code.add(code.get_pc_addr(), result.condition.cvt16());
        // }
    } else {
        code.add(code.get_pc_addr(), cast(u8) (dsp_instruction.size / 16));
    }

    final switch (result.type) {
    case DspJitResultType.DspHalted: code.mov(rax, JitExitReason.DspHalted); break;
    case DspJitResultType.Continue:  code.mov(rax, JitExitReason.BlockEnd); break;
    case DspJitResultType.IfCc:      code.mov(rax, JitExitReason.BranchTaken); break;
    }

    return DspEmissionResult(1); // 1 instruction emitted
}

void maybe_handle_sr_sxm(DspCode code, int ac_index) {
    if (code.config.sr_SXM) {
        code.mov(code.ac_lo_address(ac_index), 0);
    }
}

DspJitResult emit_abs(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.abs.d));
    code.sal(tmp, 64 - 40);
    code.mov(tmp2, tmp);
    code.neg(tmp);
    code.cmovs(tmp, tmp2);

    emit_set_flags(AllFlagsButLZAndC, Flag.C, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.abs.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_add(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(1 - instruction.add.d));
    code.mov(tmp2, code.ac_full_address(instruction.add.d));
    code.sal(tmp1, 64 - 40);
    code.sal(tmp2, 64 - 40);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);
    code.sar(tmp1, 64 - 40);

    code.mov(code.ac_full_address(instruction.add.d), tmp1);
 
    return DspJitResult.Continue;
}

DspJitResult emit_addarn(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R16 ar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 ix = code.allocate_register().cvt16();

    code.mov(ix, code.ix_address(instruction.addarn.s));
    code.mov(wr, code.wr_address(instruction.addarn.d));
    code.mov(ar, code.ar_address(instruction.addarn.d));

    R16 sum = code.allocate_register().cvt16();
    emit_wrapping_register_add(code, ar, wr, ix, sum);
    code.mov(code.ar_address(instruction.addarn.d), sum);
    
    return DspJitResult.Continue;
}

DspJitResult emit_addax(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(instruction.addax.d));
    code.mov(tmp2.cvt32(), code.ax_full_address(instruction.addax.s));
    code.movsxd(tmp2, tmp2.cvt32());

    code.sal(tmp1, 64 - 40);
    code.sal(tmp2, 64 - 40);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);
    code.sar(tmp1, 64 - 40);

    code.mov(code.ac_full_address(instruction.addax.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_addaxl(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(instruction.addaxl.d));
    code.mov(tmp2.cvt16(), code.ax_lo_address(instruction.addaxl.s));
    code.movzx(tmp2, tmp2.cvt16());

    code.sal(tmp1, 64 - 40);
    code.sal(tmp2, 64 - 40);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);
    code.sar(tmp1, 64 - 40);

    code.mov(code.ac_full_address(instruction.addaxl.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_addi(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.ac_hm_address(instruction.addi.d));
    code.mov(tmp2, sext_64(instruction.addi.i, 16) << 40);

    code.sal(tmp1, 64 - 24);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);
    code.sar(tmp1, 64 - 24);

    code.mov(code.ac_hm_address(instruction.addi.d), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_addis(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.ac_hm_address(instruction.addis.d));
    code.mov(tmp2, sext_64(instruction.addis.i, 8) << 40);

    code.sal(tmp1, 64 - 24);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);
    code.sar(tmp1, 64 - 24);

    code.mov(code.ac_hm_address(instruction.addis.d), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_addp(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);

    code.setc(tmp3.cvt8());
    code.seto(tmp4.cvt8());

    code.mov(tmp2, code.ac_full_address(instruction.addp.d));
    code.sal(tmp2, 64 - 40);
    code.add(tmp1, tmp2);

    emit_set_flags_addp(AllFlagsButLZ, 0, code, tmp1, tmp3, tmp4, tmp2, tmp5);
    code.sar(tmp1, 64 - 40);

    code.mov(code.ac_full_address(instruction.addp.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_addpaxz(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);
    code.setc(tmp5.cvt8());
    code.seto(tmp2.cvt8());
    code.mov(tmp3, tmp1);
    code.mov(tmp4, 0x10000UL << 24);
    code.and(tmp3, tmp4);
    code.sar(tmp3, 16);
    code.add(tmp1, tmp3);
    code.mov(tmp4, 0x7fffUL << 24);
    code.add(tmp1, tmp4);
    code.sar(tmp1, 40);
    code.sal(tmp1, 40);

    code.mov(tmp3.cvt16(), code.ax_hi_address(instruction.addpaxz.s));
    code.movsx(tmp3, tmp3.cvt16());
    code.sal(tmp3, 64 - 24);

    code.add(tmp1, tmp3);

    emit_set_flags_addpaxz(AllFlagsButLZ, 0, code, tmp1, tmp5, tmp2, tmp4, tmp3);

    code.sar(tmp1, 64 - 40);
    code.mov(code.ac_full_address(instruction.addpaxz.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_addr(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    final switch (instruction.addr.s) {
    case 0: code.mov(tmp1.cvt16(), code.ax_lo_address(0)); break;
    case 1: code.mov(tmp1.cvt16(), code.ax_lo_address(1)); break;
    case 2: code.mov(tmp1.cvt16(), code.ax_hi_address(0)); break;
    case 3: code.mov(tmp1.cvt16(), code.ax_hi_address(1)); break;
    }

    code.movzx(tmp1, tmp1.cvt16());

    code.mov(tmp2, code.ac_full_address(instruction.addr.d));
    code.sal(tmp1, 48);
    code.sar(tmp1, 8);
    code.sal(tmp2, 64 - 40);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);

    code.sar(tmp1, 64 - 40);
    code.mov(code.ac_full_address(instruction.addr.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_andc(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    code.mov(tmp1.cvt16(), code.ac_m_address(instruction.andc.r));
    code.mov(tmp2.cvt16(), code.ac_m_address(1 - instruction.andc.r));
    code.and(tmp1.cvt16(), tmp2.cvt16());
    
    code.mov(code.ac_m_address(instruction.andi.r), tmp1.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.andi.r));

    code.sal(tmp3, 24);
    code.sal(tmp1, 48);
    emit_set_flags_andi(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.O | Flag.C, code, tmp1, tmp3, tmp2);
    
    return DspJitResult.Continue;
}

DspJitResult emit_andcf(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    
    code.mov(tmp1.cvt16(), code.ac_m_address(instruction.andcf.r));
    code.not(tmp1.cvt16());
    code.and(tmp1.cvt16(), instruction.andcf.i);

    code.sete(tmp1.cvt8());
    code.mov(FlagState.flag_lz_addr(code), tmp1.cvt8());
    
    return DspJitResult.Continue;
}

DspJitResult emit_andf(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    
    code.mov(tmp1.cvt16(), code.ac_m_address(instruction.andf.r));
    code.and(tmp1.cvt16(), instruction.andf.i);

    code.sete(tmp1.cvt8());
    code.mov(FlagState.flag_lz_addr(code), tmp1.cvt8());
    
    return DspJitResult.Continue;
}

DspJitResult emit_andi(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    code.mov(tmp1.cvt16(), code.ac_m_address(instruction.andi.r));
    code.and(tmp1.cvt16(), instruction.andi.i);
    
    code.mov(code.ac_m_address(instruction.andi.r), tmp1.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.andi.r));

    code.sal(tmp3, 24);
    code.sal(tmp1, 48);
    emit_set_flags_andi(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.O | Flag.C, code, tmp1, tmp3, tmp2);
    
    return DspJitResult.Continue;
}

DspJitResult emit_andr(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    code.mov(tmp1.cvt16(), code.ac_m_address(instruction.andr.r));
    code.and(tmp1.cvt16(), code.ax_hi_address(instruction.andr.s));
    
    code.mov(code.ac_m_address(instruction.andr.r), tmp1.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.andr.r));

    code.sal(tmp3, 24);
    code.sal(tmp1, 48);
    emit_set_flags_andi(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.O | Flag.C, code, tmp1, tmp3, tmp2);
    
    return DspJitResult.Continue;
}

DspJitResult emit_asl(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.asl.r));
    code.sal(tmp, 64 - 40);
    code.mov(tmp2, tmp);
    code.sal(tmp, cast(u8) instruction.asl.s);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.asl.r), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_asr(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.asr.r));
    code.sal(tmp, 64 - 40);
    code.mov(tmp2, tmp);

    code.sar(tmp, cast(u8) ((-instruction.asr.s) & 0x3f));
    code.mov(tmp2, ~((1UL << 24) - 1));
    code.and(tmp, tmp2);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.asr.r), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_asrn(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(cx, code.ac_m_address(1));
    code.mov(tmp2, code.ac_full_address(0));
    code.sal(tmp2, 64 - 40);
    code.sar(tmp2, 64 - 40);

    code.and(ecx, 0x7f);
    
    code.mov(tmp1, rcx);
    code.mov(tmp3, tmp2);
    code.sar(tmp2);
    code.neg(cl);
    code.and(cl, 0x3f);
    code.sal(tmp3);
    code.test(tmp1, 0x40);
    code.cmovne(tmp2, tmp3);

    code.sal(tmp2, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp2, tmp3);
    
    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(0), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_asrnr(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(cx, code.ac_m_address(1 - instruction.asrnr.d));
    code.mov(tmp2, code.ac_full_address(instruction.asrnr.d));
    code.sal(tmp2, 64 - 40);
    code.sar(tmp2, 64 - 40);
    
    code.and(ecx, 0x7f);
    
    code.mov(tmp1, rcx);
    code.mov(tmp3, tmp2);
    code.sal(tmp2);
    code.neg(cl);
    code.and(cl, 0x3f);
    code.sar(tmp3);
    code.test(tmp1, 0x40);
    code.cmovne(tmp2, tmp3);

    code.sal(tmp2, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp2, tmp3);
    
    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(instruction.asrnr.d), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_asrnrx(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(cx, code.ax_hi_address(instruction.asrnrx.s));
    code.mov(tmp2, code.ac_full_address(instruction.asrnrx.d));
    code.sal(tmp2, 64 - 40);
    code.sar(tmp2, 64 - 40);
    
    code.and(ecx, 0x7f);
    
    code.mov(tmp1, rcx);
    code.mov(tmp3, tmp2);
    code.sal(tmp2);
    code.neg(cl);
    code.and(cl, 0x3f);
    code.sar(tmp3);
    code.test(tmp1, 0x40);
    code.cmovne(tmp2, tmp3);

    code.sal(tmp2, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp2, tmp3);
    
    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(instruction.asrnrx.d), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_asr16(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.asr16.r));
    code.sal(tmp, 64 - 40);
    code.sar(tmp, 40);

    code.sal(tmp, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);
    code.sar(tmp, 64 - 40);

    code.mov(code.ac_full_address(instruction.asr16.r), tmp);
    return DspJitResult.Continue;
}

DspJitResult emit_clr15(DspCode code, DspInstruction instruction) {
    code.and(code.sr_upper_address(), 0x7f);

    return DspJitResult.Continue;
}

DspJitResult emit_clr(DspCode code, DspInstruction instruction) {
    code.mov(code.ac_full_address(instruction.clr.r), 0);
    emit_reset_flags(code);

    return DspJitResult.Continue;
}

DspJitResult emit_clrl(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(instruction.clrl.r));
    code.mov(tmp2, tmp1);
    
    code.sar(tmp2, 16);
    code.and(tmp2, 1);

    code.add(tmp1, 0x7fff);
    code.add(tmp1, tmp2);
    code.mov(tmp2, ~0xffffUL);
    code.and(tmp1, tmp2);

    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp1, tmp2);
    
    code.sar(tmp1, 64 - 40);
    code.mov(code.ac_full_address(instruction.clrl.r), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_clrp(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();

    code.mov(tmp1, 0x00ff0010fff00000);
    code.mov(code.prod_full_address(), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_cmp(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(0));
    code.mov(tmp2, code.ac_full_address(1));
    code.sal(tmp1, 64 - 40);
    code.sal(tmp2, 64 - 40);
    code.neg(tmp2);
    code.add(tmp1, tmp2);

    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp1, tmp2, tmp3, tmp4, tmp5);

    return DspJitResult.Continue;
}

DspJitResult emit_cmpaxh(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(instruction.cmpaxh.s));
    code.mov(tmp2.cvt16(), code.ax_hi_address(instruction.cmpaxh.r));
    code.movsx(tmp2, tmp2.cvt16());
    code.sal(tmp1, 64 - 40);
    code.sal(tmp2, 64 - 24);
    code.neg(tmp2);
    code.add(tmp1, tmp2);

    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp1, tmp2, tmp3, tmp4, tmp5);

    return DspJitResult.Continue;
}

DspJitResult emit_cmpi(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.ac_hm_address(instruction.cmpi.r));
    code.mov(tmp2, sext_64(instruction.cmpi.i, 16) << 40);
    code.sal(tmp1, 64 - 24);
    code.neg(tmp2);
    code.add(tmp1, tmp2);

    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp1, tmp2, tmp3, tmp4, tmp5);

    return DspJitResult.Continue;
}

DspJitResult emit_cmpis(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.ac_hm_address(instruction.cmpis.d));
    code.mov(tmp2, sext_64(instruction.cmpis.i, 8) << 40);
    code.sal(tmp1, 64 - 24);
    code.neg(tmp2);
    code.add(tmp1, tmp2);

    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp1, tmp2, tmp3, tmp4, tmp5);

    return DspJitResult.Continue;
}

DspJitResult emit_dar(DspCode code, DspInstruction instruction) {
    R16 dar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 sum = code.allocate_register().cvt16();

    code.movzx(dar.cvt32(), code.ar_address(instruction.dar.a));
    code.movzx(wr.cvt32(),  code.wr_address(instruction.dar.a));

    emit_wrapping_register_sub_one(code, dar, wr, sum);
    code.mov(code.ar_address(instruction.dar.a), sum);

    return DspJitResult.Continue;
}

DspJitResult emit_dec(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.dec.d));
    code.sal(tmp, 64 - 40);
    code.mov(tmp3, 0xffffffffff000000);
    code.add(tmp, tmp3);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB | Flag.C | Flag.O, 0, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.dec.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_decm(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.decm.d));
    code.sal(tmp, 64 - 40);
    code.mov(tmp3, 0xffffff0000000000);
    code.add(tmp, tmp3);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB | Flag.C | Flag.O | Flag.OS, 0, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.decm.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_halt(DspCode code, DspInstruction instruction) {
    // need to set HALT bit in DREG_CR
    return DspJitResult.DspHalted;
}

DspJitResult emit_iar(DspCode code, DspInstruction instruction) {
    R16 ar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 sum = code.allocate_register().cvt16();

    code.movzx(wr.cvt32(), code.wr_address(instruction.iar.a));
    code.movzx(ar.cvt32(), code.ar_address(instruction.iar.a));

    emit_wrapping_register_add_one(code, ar, wr, sum);
    code.mov(code.ar_address(instruction.iar.a), sum);

    return DspJitResult.Continue;
}

DspJitResult emit_if_cc(DspCode code, DspInstruction instruction) {
    R32 tmp = code.allocate_register().cvt32();
    R32 result = code.allocate_register().cvt32();
    
    emit_get_condition(code, result, tmp, cast(Condition) instruction.if_cc.c);
    
    return DspJitResult.IfCc(result);
}

DspJitResult emit_inc(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.inc.d));
    code.sal(tmp, 64 - 40);
    code.mov(tmp3, 0x0000000001000000);
    code.add(tmp, tmp3);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB | Flag.C | Flag.O, 0, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.inc.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_incm(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.incm.d));
    code.sal(tmp, 64 - 40);
    code.mov(tmp3, 0x0000010000000000);
    code.add(tmp, tmp3);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB | Flag.C | Flag.O | Flag.OS, 0, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.incm.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_lsl(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.lsl.r));
    code.sal(tmp, 64 - 40);
    code.mov(tmp2, tmp);
    code.shl(tmp, cast(u8) instruction.lsl.s);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.lsl.r), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_lsl16(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.lsl16.r));
    code.sal(tmp, 64 - 40);
    code.shl(tmp, 16);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.lsl16.r), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_lsr(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.lsr.r));
    code.sal(tmp, 64 - 40);
    code.shr(tmp, cast(u8) (64 - instruction.lsr.s));
    code.mov(tmp2, ~((1UL << 24) - 1));
    code.and(tmp, tmp2);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.lsr.r), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_lsrn(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(cx, code.ac_m_address(1));
    code.mov(tmp2, code.ac_full_address(0));
    code.sal(tmp2, 64 - 40);
    code.shr(tmp2, 64 - 40);

    code.and(ecx, 0x7f);
    
    code.mov(tmp1, rcx);
    code.mov(tmp3, tmp2);
    code.shr(tmp2);
    code.neg(cl);
    code.and(cl, 0x3f);
    code.shl(tmp3);
    code.test(tmp1, 0x40);
    code.cmovne(tmp2, tmp3);

    code.sal(tmp2, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp2, tmp3);
    
    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(0), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_lsrnr(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(cx, code.ac_m_address(1 - instruction.lsrnr.d));
    code.mov(tmp2, code.ac_full_address(instruction.lsrnr.d));
    code.sal(tmp2, 64 - 40);
    code.shr(tmp2, 64 - 40);
    
    code.and(ecx, 0x7f);
    
    code.mov(tmp1, rcx);
    code.mov(tmp3, tmp2);
    code.shl(tmp2);
    code.neg(cl);
    code.and(cl, 0x3f);
    code.shr(tmp3);
    code.test(tmp1, 0x40);
    code.cmovne(tmp2, tmp3);

    code.sal(tmp2, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp2, tmp3);
    
    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(instruction.lsrnr.d), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_lsrnrx(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(cx, code.ax_hi_address(instruction.lsrnrx.s));
    code.mov(tmp2, code.ac_full_address(instruction.lsrnrx.d));
    code.sal(tmp2, 64 - 40);
    code.shr(tmp2, 64 - 40);
    
    code.and(ecx, 0x7f);
    
    code.mov(tmp1, rcx);
    code.mov(tmp3, tmp2);
    code.shl(tmp2);
    code.neg(cl);
    code.and(cl, 0x3f);
    code.shr(tmp3);
    code.test(tmp1, 0x40);
    code.cmovne(tmp2, tmp3);

    code.sal(tmp2, 64 - 40);
    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp2, tmp3);
    
    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(instruction.lsrnrx.d), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_lsr16(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.lsr16.r));
    code.sal(tmp, 64 - 40);
    code.shr(tmp, 16);
    code.mov(tmp2, ~((1UL << 24) - 1));
    code.and(tmp, tmp2);

    emit_set_flags(Flag.AZ | Flag.S | Flag.S32 | Flag.TB, Flag.C | Flag.O, code, tmp, tmp2);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.lsr16.r), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_m0(DspCode code, DspInstruction instruction) {
    code.or(code.sr_upper_address(), 0x20);
    return DspJitResult.Continue;
}

DspJitResult emit_m2(DspCode code, DspInstruction instruction) {
    code.and(code.sr_upper_address(), 0xdf);
    return DspJitResult.Continue;
}

DspJitResult emit_madd(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // calculate the full prod
    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ax_lo_address(instruction.madd.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.madd.s));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    // add to prod
    code.add(tmp1, tmp2);
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_maddc(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // calculate the full prod
    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ac_m_address(instruction.maddc.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.maddc.t));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    // add to prod with carry
    code.add(tmp1, tmp2);
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_maddx(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // calculate the full prod
    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, instruction.maddc.s == 1 ? code.ax_hi_address(0) : code.ax_lo_address(0));
    code.movsx(tmp3, instruction.maddc.t == 1 ? code.ax_hi_address(1) : code.ax_lo_address(1));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    // add to prod with carry
    code.add(tmp1, tmp2);
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mov(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1, code.ac_full_address(1 - instruction.mov.d));
    code.mov(code.ac_full_address(instruction.mov.d), tmp1);

    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.TB | Flag.S | Flag.AZ | Flag.S32, Flag.O | Flag.C, code, tmp1, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_movax(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.ax_full_address(instruction.movax.s));
    code.sal(tmp1, 32);
    code.sar(tmp1, 32);
    code.mov(code.ac_full_address(instruction.movax.d), tmp1);

    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.TB | Flag.S | Flag.AZ | Flag.S32, Flag.O | Flag.C, code, tmp1, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_movnp(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.neg(tmp1);

    code.mov(code.ac_full_address(instruction.movnp.d), tmp1);
    
    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.TB | Flag.S | Flag.AZ | Flag.S32 | Flag.O | Flag.C, 0, code, tmp1, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_movp(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(code.ac_full_address(instruction.movp.d), tmp1);
    
    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.TB | Flag.S | Flag.AZ | Flag.S32 | Flag.O | Flag.C, 0, code, tmp1, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_movpz(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);
    code.mov(tmp3, tmp1);
    code.mov(tmp4, 0x10000UL << 24);
    code.and(tmp3, tmp4);
    code.sar(tmp3, 16);
    code.add(tmp1, tmp3);
    code.mov(tmp4, 0x7fffUL << 24);
    code.add(tmp1, tmp4);
    code.sar(tmp1, 24);

    code.mov(tmp2, ~0xffffUL);
    code.and(tmp1, tmp2);

    code.mov(code.ac_full_address(instruction.movp.d), tmp1);
    
    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.TB | Flag.S | Flag.AZ | Flag.S32 | Flag.O | Flag.C, 0, code, tmp1, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_movr(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    final switch (instruction.movr.s) {
        case 0: code.movsx(tmp1.cvt32(), code.ax_lo_address(0)); break;
        case 1: code.movsx(tmp1.cvt32(), code.ax_lo_address(1)); break;
        case 2: code.movsx(tmp1.cvt32(), code.ax_hi_address(0)); break;
        case 3: code.movsx(tmp1.cvt32(), code.ax_hi_address(1)); break;
    }

    code.sal(tmp1, 32);
    code.sar(tmp1, 16);
    code.mov(code.ac_full_address(instruction.movr.d), tmp1);

    code.sal(tmp1, 64 - 40);
    emit_set_flags(Flag.TB | Flag.S | Flag.AZ | Flag.S32, Flag.O | Flag.C, code, tmp1, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_mrr(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();

    read_arbitrary_reg(code, tmp1, instruction.mrr.s);
    write_arbitrary_reg(code, tmp1, instruction.mrr.d);

    return DspJitResult.Continue;
}

DspJitResult emit_msub(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // calculate the full prod
    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ax_lo_address(instruction.msub.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.msub.s));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    // sub from prod
    code.neg(tmp2);
    code.add(tmp1, tmp2);
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_msubc(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // calculate the full prod
    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ac_m_address(instruction.msubc.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.msubc.t));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    // sub from prod
    code.neg(tmp2);
    code.add(tmp1, tmp2);
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_msubx(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // calculate the full prod
    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, instruction.msubc.s == 1 ? code.ax_hi_address(0) : code.ax_lo_address(0));
    code.movsx(tmp3, instruction.msubc.t == 1 ? code.ax_hi_address(1) : code.ax_lo_address(1));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    // sub from prod
    code.neg(tmp2);
    code.add(tmp1, tmp2);
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mul(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    code.movsx(tmp1, code.ax_lo_address(instruction.mul.s));
    code.movsx(tmp2, code.ax_hi_address(instruction.mul.s));
    code.imul(tmp1, tmp2);
    code.mov(tmp2, (1UL << 48) - 1);
    code.and(tmp1, tmp2);

    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);
    
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulac(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp5, code.ac_full_address(instruction.mulac.r));
    code.sal(tmp5, 64 - 40);
    code.sar(tmp5, 64 - 40);
    code.add(tmp1, tmp5);
    code.mov(code.ac_full_address(instruction.mulac.r), tmp1);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ax_lo_address(instruction.mulac.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.mulac.s));
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    code.mov(code.prod_lo_m1_address(), tmp2.cvt32());
    code.sar(tmp2, 32);
    code.sal(tmp2, 16);
    code.mov(code.prod_m2_hi_address(), tmp2.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulaxh(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    code.movsx(tmp1, code.ax_hi_address(0));
    code.imul(tmp1, tmp1);
    code.mov(tmp2, (1UL << 48) - 1);
    code.and(tmp1, tmp2);

    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);
    
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulc(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    code.movsx(tmp1, code.ac_m_address(instruction.mulc.s));
    code.movsx(tmp2, code.ax_hi_address(instruction.mulc.t));
    code.imul(tmp1, tmp2);
    code.mov(tmp2, (1UL << 48) - 1);
    code.and(tmp1, tmp2);

    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);
    
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulcac(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp5, code.ac_full_address(instruction.mulcac.r));
    code.sal(tmp5, 64 - 40);
    code.sar(tmp5, 64 - 40);
    code.add(tmp1, tmp5);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ac_m_address(instruction.mulcac.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.mulcac.t));
    code.mov(code.ac_full_address(instruction.mulcac.r), tmp1);
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    code.mov(code.prod_lo_m1_address(), tmp2.cvt32());
    code.sar(tmp2, 32);
    code.sal(tmp2, 16);
    code.mov(code.prod_m2_hi_address(), tmp2.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulcmv(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ac_m_address(instruction.mulcmv.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.mulcmv.t));
    code.mov(code.ac_full_address(instruction.mulcmv.r), tmp1);
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    code.mov(code.prod_lo_m1_address(), tmp2.cvt32());
    code.sar(tmp2, 32);
    code.sal(tmp2, 16);
    code.mov(code.prod_m2_hi_address(), tmp2.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulcmvz(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);
    code.setc(tmp5.cvt8());
    code.seto(tmp2.cvt8());
    code.mov(tmp3, tmp1);
    code.mov(tmp4, 0x10000UL << 24);
    code.and(tmp3, tmp4);
    code.sar(tmp3, 16);
    code.add(tmp1, tmp3);
    code.mov(tmp4, 0x7fffUL << 24);
    code.add(tmp1, tmp4);
    code.sar(tmp1, 40);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);
    code.sal(tmp1, 16);

    code.movsx(tmp2, code.ac_m_address(instruction.mulcmv.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.mulcmv.t));
    code.mov(code.ac_full_address(instruction.mulcmv.r), tmp1);
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    code.mov(code.prod_lo_m1_address(), tmp2.cvt32());
    code.sar(tmp2, 32);
    code.sal(tmp2, 16);
    code.mov(code.prod_m2_hi_address(), tmp2.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulmv(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    code.movsx(tmp2, code.ax_lo_address(instruction.mulmv.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.mulmv.s));
    code.mov(code.ac_full_address(instruction.mulmv.r), tmp1);
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    code.mov(code.prod_lo_m1_address(), tmp2.cvt32());
    code.sar(tmp2, 32);
    code.sal(tmp2, 16);
    code.mov(code.prod_m2_hi_address(), tmp2.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulmvz(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);
    code.setc(tmp5.cvt8());
    code.seto(tmp2.cvt8());
    code.mov(tmp3, tmp1);
    code.mov(tmp4, 0x10000UL << 24);
    code.and(tmp3, tmp4);
    code.sar(tmp3, 16);
    code.add(tmp1, tmp3);
    code.mov(tmp4, 0x7fffUL << 24);
    code.add(tmp1, tmp4);
    code.sar(tmp1, 40);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);
    code.sal(tmp1, 16);

    code.movsx(tmp2, code.ax_lo_address(instruction.mulmv.s));
    code.movsx(tmp3, code.ax_hi_address(instruction.mulmv.s));
    code.mov(code.ac_full_address(instruction.mulmv.r), tmp1);
    code.imul(tmp2, tmp3);
    code.and(tmp2, tmp4);
    
    code.mov(tmp5.cvt8(), code.sr_upper_address());
    code.mov(tmp4, tmp2);
    code.sal(tmp4, 1);
    code.test(tmp5.cvt8(), 0x20);
    code.cmovz(tmp2, tmp4);

    code.mov(code.prod_lo_m1_address(), tmp2.cvt32());
    code.sar(tmp2, 32);
    code.sal(tmp2, 16);
    code.mov(code.prod_m2_hi_address(), tmp2.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulx(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    
    auto s = instruction.mulx.s;
    auto t = instruction.mulx.t;

    if (s && t) {
        // both high
        code.movsx(tmp1, code.ax_hi_address(0));
        code.movsx(tmp2, code.ax_hi_address(1));
    } else {
        R64 su = code.allocate_register();
        code.mov(su.cvt8(), code.sr_upper_address());
        code.and(su.cvt8(), 0x80);

        auto all_signed = code.fresh_label();
        auto done = code.fresh_label();
        code.je(all_signed);

        if (!s && !t) {
            // both low
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else if (s && !t) {
            // s high, t low
            code.movsx(tmp1, code.ax_hi_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else {
            // s low, t high
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movsx(tmp2, code.ax_hi_address(1));
        }
        code.jmp(done);

        code.label(all_signed);
        code.movsx(tmp1, s ? code.ax_hi_address(0) : code.ax_lo_address(0));
        code.movsx(tmp2, t ? code.ax_hi_address(1) : code.ax_lo_address(1));

        code.label(done);
    }

    code.imul(tmp1, tmp2);
    code.mov(tmp2, (1UL << 48) - 1);
    code.and(tmp1, tmp2);

    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);
    
    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulxac(DspCode code, DspInstruction instruction) {
    // same as mulx, but adds prod to acr first
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);
    code.mov(tmp5, code.ac_full_address(instruction.mulxac.r));
    code.sal(tmp5, 64 - 40);
    code.sar(tmp5, 64 - 40);
    code.add(tmp1, tmp5);
    code.mov(code.ac_full_address(instruction.mulxac.r), tmp1);
    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    auto s = instruction.mulxac.s;
    auto t = instruction.mulxac.t;

    if (s && t) {
        // both high
        code.movsx(tmp1, code.ax_hi_address(0));
        code.movsx(tmp2, code.ax_hi_address(1));
    } else {
        R64 su = code.allocate_register();
        code.mov(su.cvt8(), code.sr_upper_address());
        code.and(su.cvt8(), 0x80);

        auto all_signed = code.fresh_label();
        auto done = code.fresh_label();
        code.je(all_signed);

        if (!s && !t) {
            // both low
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else if (s && !t) {
            // s high, t low
            code.movsx(tmp1, code.ax_hi_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else {
            // s low, t high
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movsx(tmp2, code.ax_hi_address(1));
        }
        code.jmp(done);

        code.label(all_signed);
        code.movsx(tmp1, s ? code.ax_hi_address(0) : code.ax_lo_address(0));
        code.movsx(tmp2, t ? code.ax_hi_address(1) : code.ax_lo_address(1));

        code.label(done);
    }

    code.imul(tmp1, tmp2);
    code.and(tmp1, tmp4);
    
    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);

    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_mulxmv(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp2, 16);
    code.add(tmp1, tmp2);
    code.mov(code.ac_full_address(instruction.mulxac.r), tmp1);
    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);

    auto s = instruction.mulxac.s;
    auto t = instruction.mulxac.t;

    if (s && t) {
        // both high
        code.movsx(tmp1, code.ax_hi_address(0));
        code.movsx(tmp2, code.ax_hi_address(1));
    } else {
        R64 su = code.allocate_register();
        code.mov(su.cvt8(), code.sr_upper_address());
        code.and(su.cvt8(), 0x80);

        auto all_signed = code.fresh_label();
        auto done = code.fresh_label();
        code.je(all_signed);

        if (!s && !t) {
            // both low
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else if (s && !t) {
            // s high, t low
            code.movsx(tmp1, code.ax_hi_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else {
            // s low, t high
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movsx(tmp2, code.ax_hi_address(1));
        }
        code.jmp(done);

        code.label(all_signed);
        code.movsx(tmp1, s ? code.ax_hi_address(0) : code.ax_lo_address(0));
        code.movsx(tmp2, t ? code.ax_hi_address(1) : code.ax_lo_address(1));

        code.label(done);
    }

    code.imul(tmp1, tmp2);
    code.and(tmp1, tmp4);
    
    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);

    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());
    
    return DspJitResult.Continue;
}

DspJitResult emit_mulxmvz(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);
    code.setc(tmp5.cvt8());
    code.seto(tmp2.cvt8());
    code.mov(tmp3, tmp1);
    code.mov(tmp4, 0x10000UL << 24);
    code.and(tmp3, tmp4);
    code.sar(tmp3, 16);
    code.add(tmp1, tmp3);
    code.mov(tmp4, 0x7fffUL << 24);
    code.add(tmp1, tmp4);
    code.sar(tmp1, 40);

    code.mov(tmp4, ((1UL << 48) - 1));
    code.and(tmp1, tmp4);
    code.sal(tmp1, 16);

    code.mov(code.ac_full_address(instruction.mulxac.r), tmp1);

    auto s = instruction.mulxac.s;
    auto t = instruction.mulxac.t;

    if (s && t) {
        // both high
        code.movsx(tmp1, code.ax_hi_address(0));
        code.movsx(tmp2, code.ax_hi_address(1));
    } else {
        R64 su = code.allocate_register();
        code.mov(su.cvt8(), code.sr_upper_address());
        code.and(su.cvt8(), 0x80);

        auto all_signed = code.fresh_label();
        auto done = code.fresh_label();
        code.je(all_signed);

        if (!s && !t) {
            // both low
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else if (s && !t) {
            // s high, t low
            code.movsx(tmp1, code.ax_hi_address(0));
            code.movzx(tmp2, code.ax_lo_address(1));
        } else {
            // s low, t high
            code.movzx(tmp1, code.ax_lo_address(0));
            code.movsx(tmp2, code.ax_hi_address(1));
        }
        code.jmp(done);

        code.label(all_signed);
        code.movsx(tmp1, s ? code.ax_hi_address(0) : code.ax_lo_address(0));
        code.movsx(tmp2, t ? code.ax_hi_address(1) : code.ax_lo_address(1));

        code.label(done);
    }

    code.imul(tmp1, tmp2);
    code.and(tmp1, tmp4);
    
    code.mov(tmp2.cvt8(), code.sr_upper_address());
    code.mov(tmp3, tmp1);
    code.sal(tmp3, 1);
    code.test(tmp2.cvt8(), 0x20);
    code.cmovz(tmp1, tmp3);

    code.mov(code.prod_lo_m1_address(), tmp1.cvt32());
    code.sar(tmp1, 32);
    code.sal(tmp1, 16);
    code.mov(code.prod_m2_hi_address(), tmp1.cvt32());
    
    return DspJitResult.Continue;
}

DspJitResult emit_neg(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.abs.d));
    code.sal(tmp, 64 - 40);
    code.neg(tmp);

    emit_set_flags_neg(AllFlagsButLZ, 0, code, tmp, tmp2, tmp3);

    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.abs.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_nop(DspCode code, DspInstruction instruction) {
    return DspJitResult.Continue;
}

DspJitResult emit_not(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.abs.d));
    code.not(tmp);
    code.mov(code.ac_m_address(instruction.abs.d), tmp.cvt16());

    code.mov(tmp2, code.ac_full_address(instruction.abs.d));
    code.sal(tmp2, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp2, tmp3);

    return DspJitResult.Continue;
}

DspJitResult emit_orc(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.orc.r));
    code.movzx(tmp2, code.ac_m_address(1 - instruction.orc.r));
    code.or(tmp, tmp2);
    code.mov(code.ac_m_address(instruction.orc.r), tmp.cvt16());

    code.mov(tmp3, code.ac_full_address(instruction.orc.r));

    code.sal(tmp3, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp3, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_ori(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.ori.r));
    code.or(tmp, instruction.ori.i);
    code.mov(code.ac_m_address(instruction.ori.r), tmp.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.ori.r));
    
    code.sal(tmp3, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp3, tmp2);
    
    return DspJitResult.Continue;
}

DspJitResult emit_orr(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.orr.r));
    code.movsx(tmp2, code.ax_hi_address(instruction.orr.s));
    code.or(tmp, tmp2);
    code.mov(code.ac_m_address(instruction.orr.r), tmp.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.orr.r));
    
    code.sal(tmp3, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp3, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_sbclr(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();

    int bit = 6 + instruction.sbclr.i;

    if (bit == 6) {
        code.mov(FlagState.flag_lz_addr(code), 0);
    } else if (bit == 7) {
        code.mov(FlagState.flag_os_addr(code), 0); 
    } else if (bit != 8 && bit != 13) {
        bit -= 8;
        code.mov(tmp.cvt8(), code.sr_upper_address());
        code.and(tmp.cvt8(), cast(u8) ~(1 << bit));
        code.mov(code.sr_upper_address(), tmp.cvt8());
    }

    return DspJitResult.Continue;
}

DspJitResult emit_sbset(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();

    int bit = 6 + instruction.sbclr.i;

    if (bit == 6) {
        code.mov(FlagState.flag_lz_addr(code), 1);
    } else if (bit == 7) {
        code.mov(FlagState.flag_os_addr(code), 1); 
    } else if (bit != 8 && bit != 13) {
        bit -= 8;
        code.mov(tmp.cvt8(), code.sr_upper_address());
        code.or(tmp.cvt8(), cast(u8) (1 << bit));
        code.mov(code.sr_upper_address(), tmp.cvt8());
    }

    return DspJitResult.Continue;
}

DspJitResult emit_set15(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    code.mov(tmp.cvt8(), code.sr_upper_address());
    code.or(tmp.cvt8(), 0x80);
    code.mov(code.sr_upper_address(), tmp.cvt8());

    return DspJitResult.Continue;
}

DspJitResult emit_set16(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    code.mov(tmp.cvt8(), code.sr_upper_address());
    code.and(tmp.cvt8(), cast(u8) ~0x40);
    code.mov(code.sr_upper_address(), tmp.cvt8());

    return DspJitResult.Continue;
}

DspJitResult emit_set40(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    code.mov(tmp.cvt8(), code.sr_upper_address());
    code.or(tmp.cvt8(), 0x40);
    code.mov(code.sr_upper_address(), tmp.cvt8());

    return DspJitResult.Continue;
}

DspJitResult emit_sub(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    // Subtracts accumulator $ac(1-D) from accumulator register $acD

    code.mov(tmp, code.ac_full_address(instruction.sub.d));
    code.mov(tmp2, code.ac_full_address(1 - instruction.sub.d));
    code.sal(tmp, 64 - 40);
    code.sal(tmp2, 64 - 40);

    code.neg(tmp2);
    code.add(tmp, tmp2);
    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp, tmp2, tmp3, tmp4, tmp5);
    
    code.sar(tmp, 64 - 40);
    code.mov(code.ac_full_address(instruction.sub.d), tmp);

    return DspJitResult.Continue;
}

DspJitResult emit_subarn(DspCode code, DspInstruction instruction) {
    code.reserve_register(rcx);

    R16 ar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 ix = code.allocate_register().cvt16();

    code.mov(ix, code.ix_address(instruction.subarn.d));
    code.mov(wr, code.wr_address(instruction.subarn.d));
    code.mov(ar, code.ar_address(instruction.subarn.d));
    code.neg(ix.cvt32());

    R16 sum = code.allocate_register().cvt16();
    emit_wrapping_register_sub(code, ar, wr, ix, sum);
    code.mov(code.ar_address(instruction.subarn.d), sum);
    
    return DspJitResult.Continue;
}

DspJitResult emit_subax(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();


    code.mov(tmp1, code.ac_full_address(instruction.subax.d));
    code.mov(tmp2.cvt32(), code.ax_full_address(instruction.subax.s));
    code.movsxd(tmp2, tmp2.cvt32());

    code.sal(tmp1, 64 - 40);
    code.sal(tmp2, 64 - 40);
    code.neg(tmp2);
    code.add(tmp1, tmp2);

    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp1, tmp2, tmp3, tmp4, tmp5);
    code.sar(tmp1, 64 - 40);

    code.mov(code.ac_full_address(instruction.subax.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_subp(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();
    R64 tmp6 = code.allocate_register();
    R64 tmp7 = code.allocate_register();

    code.mov(tmp1.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp1, 24);
    code.sal(tmp2, 40);
    code.add(tmp1, tmp2);

    code.setc(tmp6.cvt8());
    code.seto(tmp7.cvt8());

    code.mov(tmp2, code.ac_full_address(instruction.subp.d));
    code.sal(tmp2, 64 - 40);
    code.neg(tmp1);
    code.mov(tmp3, tmp1);
    code.add(tmp1, tmp2);

    emit_set_flags_subp(AllFlagsButLZ, 0, code, tmp1, tmp3, tmp6, tmp7, tmp4, tmp2, tmp5);
    code.sar(tmp1, 64 - 40);

    code.mov(code.ac_full_address(instruction.subp.d), tmp1);

    return DspJitResult.Continue;
}

DspJitResult emit_subr(DspCode code, DspInstruction instruction) {
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();
    R64 tmp4 = code.allocate_register();
    R64 tmp5 = code.allocate_register();

    final switch (instruction.addr.s) {
    case 0: code.mov(tmp1.cvt16(), code.ax_lo_address(0)); break;
    case 1: code.mov(tmp1.cvt16(), code.ax_lo_address(1)); break;
    case 2: code.mov(tmp1.cvt16(), code.ax_hi_address(0)); break;
    case 3: code.mov(tmp1.cvt16(), code.ax_hi_address(1)); break;
    }

    code.movzx(tmp1, tmp1.cvt16());

    code.mov(tmp2, code.ac_full_address(instruction.addr.d));
    code.sal(tmp1, 48);
    code.sar(tmp1, 8);
    code.sal(tmp2, 64 - 40);
    code.neg(tmp1);
    code.add(tmp2, tmp1);

    emit_set_flags_sub(AllFlagsButLZ, 0, code, tmp2, tmp1, tmp3, tmp4, tmp5);

    code.sar(tmp2, 64 - 40);
    code.mov(code.ac_full_address(instruction.addr.d), tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_tst(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp, code.ac_full_address(instruction.tst.r));
    code.sal(tmp, 64 - 40);

    emit_set_flags(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_tstaxh(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.movzx(tmp, code.ax_hi_address(instruction.tstaxh.r));
    code.sal(tmp, 64 - 16);
    code.sar(tmp, 8);

    emit_set_flags(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_tstprod(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();

    code.mov(tmp.cvt32(), code.prod_lo_m1_address());
    code.mov(tmp2.cvt32(), code.prod_m2_hi_address());
    code.sal(tmp, 24);
    code.sal(tmp2, 40);
    code.add(tmp, tmp2);

    emit_set_flags(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_xorc(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.xorc.d));
    code.movzx(tmp2, code.ac_m_address(1 - instruction.xorc.d));
    code.xor(tmp, tmp2);
    code.mov(code.ac_m_address(instruction.xorc.d), tmp.cvt16());

    code.mov(tmp3, code.ac_full_address(instruction.xorc.d));

    code.sal(tmp3, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp3, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_xori(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.xori.r));
    code.xor(tmp, instruction.xori.i);
    code.mov(code.ac_m_address(instruction.xori.r), tmp.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.xori.r));
    
    code.sal(tmp3, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp3, tmp2);
    
    return DspJitResult.Continue;
}

DspJitResult emit_xorr(DspCode code, DspInstruction instruction) {
    R64 tmp = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    R64 tmp3 = code.allocate_register();

    code.movzx(tmp, code.ac_m_address(instruction.xorr.r));
    code.movsx(tmp2, code.ax_hi_address(instruction.xorr.s));
    code.xor(tmp, tmp2);
    code.mov(code.ac_m_address(instruction.xorr.r), tmp.cvt16());
    code.mov(tmp3, code.ac_full_address(instruction.xorr.r));
    
    code.sal(tmp3, 64 - 40);
    code.sal(tmp, 64 - 16);
    emit_set_flags_not(Flag.TB | Flag.S32 | Flag.AZ | Flag.S, Flag.C | Flag.O, code, tmp, tmp3, tmp2);

    return DspJitResult.Continue;
}

DspJitResult emit_instruction(DspCode code, DspInstruction dsp_instruction) {
    switch (dsp_instruction.opcode) {
        static foreach (opcode; EnumMembers!DspOpcode) {{
            enum bool is_target(alias T) = T == "emit_" ~ opcode.stringof.toLower;
            
            static if (Filter!(is_target, __traits(allMembers, emu.hw.dsp.jit.emission.emit)).length > 0) {
                case opcode:
                    mixin("return emit_" ~ opcode.stringof.toLower ~ "(code, dsp_instruction);");
            }
        }}

        default: 
            error_dsp("Unimplemented DSP instruction: %s", dsp_instruction);
            return DspJitResult.DspHalted;
    }
}