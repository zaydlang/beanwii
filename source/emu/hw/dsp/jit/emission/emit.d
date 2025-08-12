module emu.hw.dsp.jit.emission.emit;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.jit;
import emu.hw.dsp.jit.memory;
import util.number;
import util.log;

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

DspJitResult emit_halt(DspCode code) {
    return DspJitResult.DspHalted;
}

DspJitResult emit_instruction(DspCode code, DspInstruction dsp_instruction) {
    switch (dsp_instruction.opcode) {
        case DspOpcode.HALT: return emit_halt(code);
        
        // do nothing for now
        default: return DspJitResult.Continue;
    }
}