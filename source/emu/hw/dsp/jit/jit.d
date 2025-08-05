module emu.hw.dsp.jit.jit;

import emu.hw.dsp.jit.page_table;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.emit;
import emu.hw.dsp.state;
import util.log;
import util.number;

enum DspJitResult : u32 {
    Continue  = 0,
    DspHalted = 1,
}

final class DspJit {
    DspPageTable page_table;
    CodeBlockTracker codeblocks;
    DspCode code;

    this() {
        page_table = new DspPageTable();
        codeblocks = new CodeBlockTracker();
        code       = new DspCode();
    }

    DspJitResult run(DspState* state) {
        u16 pc = state.addressing_register;
        
        if (page_table.has(pc)) {
            DspJitEntry entry = page_table.get(pc);
            return execute_compiled_block(entry.func, state);
        } else {
            return compile_and_execute(state, pc);
        }
    }

    void invalidate_code_cache() {
        codeblocks = new CodeBlockTracker();
    }

    void invalidate_range(u16 start, u16 end) {
        page_table.invalidate_range(start, end);
    }

    DspJitResult compile_and_execute(DspState* state, u16 pc) {
        code.init();

        DspEmissionResult emission_result = emit_dsp_block(code, pc);
        u8[] bytes = code.get();

        void* executable_code = codeblocks.put(bytes.ptr, bytes.length);
        DspJitFunction func = cast(DspJitFunction) executable_code;
        
        DspJitEntry entry = DspJitEntry(
            func,
            cast(u16) emission_result.instruction_count,
            true
        );
        page_table.put(pc, entry);
        
        return execute_compiled_block(func, state);
    }

    DspJitResult execute_compiled_block(DspJitFunction func, DspState* state) {
        u32 result = func(cast(void*) state);
        return cast(DspJitResult) result;
    }
}