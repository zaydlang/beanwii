module emu.hw.dsp.jit.emission.emit;

import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.jit;
import util.number;

struct DspEmissionResult {
    u32 instruction_count;
}

DspEmissionResult emit_dsp_block(DspCode code, u16 pc) {
    code.mov(rax, DspJitResult.DspHalted);
    
    return DspEmissionResult(0); // 1 instruction emitted
}