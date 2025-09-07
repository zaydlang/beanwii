module emu.hw.dsp.jit.emission.emit;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.emission.flags;
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
    log_dsp("Emitting DSP block at PC: 0x%04x", pc);

    u16 current_instruction = dsp_mem.read(pc);
    u16 next_instruction    = dsp_mem.read(cast(u16) (pc + 1));
    DspInstruction dsp_instruction = decode_instruction(current_instruction, next_instruction);

    DspJitResult result = emit_instruction(code, dsp_instruction);
    log_dsp("Emitted instruction: %s %d", dsp_instruction, cast(int) result);

    code.add(code.get_pc_addr(), cast(u8) (dsp_instruction.size / 16));
    code.mov(rax, result);
    
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

    R16 ar   = code.allocate_register().cvt16();
    R16 wr   = code.allocate_register().cvt16();
    R16 ix   = code.allocate_register().cvt16();
    R16 n    = code.allocate_register().cvt16();
    R16 mask = code.allocate_register().cvt16();
    R16 sum  = code.allocate_register().cvt16();
    R16 tmp  = code.allocate_register().cvt16();

    code.mov(ix, code.ix_address(instruction.addarn.s));
    code.mov(wr, code.wr_address(instruction.addarn.d));
    code.mov(ar, code.ar_address(instruction.addarn.d));

    code.movzx(ix.cvt32(), ix);
    code.movzx(wr.cvt32(), wr);
    code.movzx(ar.cvt32(), ar);

    // source for this algorithm, the legendary duo:
    //    https://github.com/hrydgard for coming up with the initial algorithm     
    //    https://github.com/calc84maniac for refining it to this form

    // let N be the number of significant bits in WR, with a minimum of 1
    code.mov(n, wr);
    code.or(n, 1);
    code.bsr(n, n);
    code.add(n, 1);

    // create a mask out of N
    code.mov(mask, 1);
    code.mov(cl, n.cvt8());
    code.shl(mask.cvt32());
    code.sub(mask.cvt32(), 1);

    // let SUM be REG + IX...
    code.mov(sum.cvt32(), ar.cvt32());
    code.add(sum.cvt32(), ix.cvt32());

    // and let CARRY be the carry out of the low N bits of that addition
    R16 carry = ar;
    code.and(ar, mask);
    code.movzx(tmp.cvt32(), ix);
    code.and(tmp, mask);
    code.add(carry.cvt32(), tmp.cvt32());
    code.shr(carry.cvt32());
    code.and(carry, 1);

    // if IX >= 0 ...
    auto ix_negative = code.fresh_label();
    auto done = code.fresh_label();

    code.cmp(ix, 0);
    code.jl(ix_negative);

    // if CARRY == 1:
    code.cmp(carry, 0);
    code.je(done);

    // let SUM be SUM - WR - 1
    code.add(wr, 1);
    code.sub(sum, wr);
    code.jmp(done);

code.label(ix_negative);
    // if CARRY == 0 or the low N bits of SUM is less than the low N bits of ~WR:
    auto underflow = code.fresh_label();
    code.cmp(carry, 0);
    code.je(underflow);
    code.mov(tmp, wr);
    code.not(tmp);

    // reuse ix since it's no longer needed
    code.mov(ix, sum);
    code.and(ix, mask);
    code.and(tmp, mask);
    code.cmp(ix, tmp);
    code.jb(underflow);
    code.jmp(done);

code.label(underflow);
    // let SUM be SUM + (WR + 1)
    code.add(wr, 1);
    code.add(sum, wr);

code.label(done);
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

    log_dsp("ADDI d=%d i=0x%04x", instruction.addi.d, instruction.addi.i);
    code.mov(tmp1.cvt32(), code.ac_hm_address(instruction.addi.d));
    code.mov(tmp2, sext_64(instruction.addi.i, 16) << 40);

    code.sal(tmp1, 64 - 24);
    code.add(tmp1, tmp2);

    emit_set_flags(AllFlagsButLZ, 0, code, tmp1, tmp2);
    code.sar(tmp1, 64 - 24);

    code.mov(code.ac_hm_address(instruction.addi.d), tmp1.cvt32());

    return DspJitResult.Continue;
}

DspJitResult emit_halt(DspCode code, DspInstruction instruction) {
    return DspJitResult.DspHalted;
}

DspJitResult emit_nop(DspCode code, DspInstruction instruction) {
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