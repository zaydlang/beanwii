module emu.hw.dsp.jit.emission.emit;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.emission.flags;
import emu.hw.dsp.jit.jit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import gallinule.x86;
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
    u16 next_instruction    = dsp_mem.read(cast(u16) (pc + 2));
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