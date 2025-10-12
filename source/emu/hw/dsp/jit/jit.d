module emu.hw.dsp.jit.jit;

import emu.hw.dsp.jit.page_table;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.emit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import gallinule.x86;
import util.bitop;
import util.log;
import util.number;

enum JitExitReason {
    BlockEnd    = 0,
    BranchTaken = 1,
    DspHalted   = 2,
}

enum DspJitResultType {
    Continue  = 0,
    DspHalted = 1,
    IfCc      = 2,
}

struct DspJitResult {
    this(DspJitResultType type) {
        this.type = type;
    }

    this(DspJitResultType type, R32 condition) {
        this.type = type;
        this.condition = condition;
    }

    DspJitResultType type;
    R32 condition; // only valid if type == IfCc

    static DspJitResult Continue() {
        return DspJitResult(DspJitResultType.Continue);
    }

    static DspJitResult DspHalted() {
        return DspJitResult(DspJitResultType.DspHalted);
    }

    static DspJitResult IfCc(R32 condition) {
        return DspJitResult(DspJitResultType.IfCc, condition);
    }
}

final class DspJit {
    DspPageTable page_table;
    CodeBlockTracker codeblocks;
    DspCode code;
    DspMemory dsp_memory;

    this() {
        page_table = new DspPageTable();
        codeblocks = new CodeBlockTracker();
        code       = new DspCode();
        dsp_memory = new DspMemory();
    }

    JitExitReason run(DspState* state) {
        u32 config_bitfield = get_config_bitfield(state);
        if (page_table.has(state.pc, config_bitfield)) {
            DspJitEntry entry = page_table.get(state.pc, config_bitfield);
            return execute_compiled_block(entry.func, state);
        } else {
            return compile_and_execute(state, state.pc);
        }
    }

    private u32 get_config_bitfield(DspState* state) {
        u32 bitfield = 0;
        if (state.sr_upper.bit(14 - 8)) bitfield |= 1; // sr_SXM
        return bitfield;
    }

    void invalidate_code_cache() {
        codeblocks = new CodeBlockTracker();
    }

    void invalidate_range(u16 start, u16 end) {
        page_table.invalidate_range(start, end);
    }

    JitExitReason compile_and_execute(DspState* state, u16 pc) {
        code.init(state);

        DspEmissionResult emission_result = emit_dsp_block(code, dsp_memory, pc);
        u8[] bytes = code.get();

        void* executable_code = codeblocks.put(bytes.ptr, bytes.length);
        DspJitFunction func = cast(DspJitFunction) executable_code;
        
        DspJitEntry entry = DspJitEntry(
            func,
            cast(u16) emission_result.instruction_count,
            true
        );
        u32 config_bitfield = get_config_bitfield(state);
        page_table.put(pc, config_bitfield, entry);
        
        return execute_compiled_block(func, state);
    }

    JitExitReason execute_compiled_block(DspJitFunction func, DspState* state) {
        u32 result = func(cast(void*) state);
        return cast(JitExitReason) result;
    }

    void upload_iram(u16[] iram) {
        dsp_memory.upload_iram(iram);
    }

    // used for tests
    void single_step_until_halt(DspState* state) {
        while (compile_and_execute(state, state.pc) != JitExitReason.DspHalted) {}
    }
}