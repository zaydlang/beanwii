module emu.hw.dsp.jit.jit;

import emu.hw.dsp.jit.page_table;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.emit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import emu.hw.dsp.dsp;
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
    Call      = 3,
    CallCc    = 4,
    CallR     = 5,
    CallRcc   = 6,
    Jmp       = 7,
    JmpCc     = 8,
    JmpR      = 9,
    JmpRcc    = 10,
    RetCc     = 11,
    RtiCc     = 12,
}

struct DspJitResult {
    this(DspJitResultType type) {
        this.type = type;
    }

    this(DspJitResultType type, R32 condition) {
        this.type = type;
        this.condition = condition;
    }

    this(DspJitResultType type, u16 target_address) {
        this.type = type;
        this.target_address = target_address;
    }

    this(DspJitResultType type, R32 condition, u16 target_address) {
        this.type = type;
        this.condition = condition;
        this.target_address = target_address;
    }

    this(DspJitResultType type, R32 condition, R32 target_register) {
        this.type = type;
        this.condition = condition;
        this.target_register = target_register;
    }


    DspJitResultType type;
    R32 condition; // only valid if type == IfCc, CallCc, CallRcc, RetCc, or RtiCc
    u16 target_address; // only valid if type == Call or CallCc
    R32 target_register; // only valid if type == CallR or CallRcc

    static DspJitResult Continue() {
        return DspJitResult(DspJitResultType.Continue);
    }

    static DspJitResult DspHalted() {
        return DspJitResult(DspJitResultType.DspHalted);
    }

    static DspJitResult IfCc(R32 condition) {
        return DspJitResult(DspJitResultType.IfCc, condition);
    }

    static DspJitResult Call(u16 target_address) {
        return DspJitResult(DspJitResultType.Call, target_address);
    }

    static DspJitResult CallCc(R32 condition, u16 target_address) {
        return DspJitResult(DspJitResultType.CallCc, condition, target_address);
    }

    static DspJitResult CallR(u16 target_register) {
        return DspJitResult(DspJitResultType.CallR, target_register);
    }

    static DspJitResult CallRcc(R32 condition, u16 target_register) {
        return DspJitResult(DspJitResultType.CallRcc, condition, target_register);
    }

    static DspJitResult Jmp(u16 target_address) {
        return DspJitResult(DspJitResultType.Jmp, target_address);
    }

    static DspJitResult JmpCc(R32 condition, u16 target_address) {
        return DspJitResult(DspJitResultType.JmpCc, condition, target_address);
    }

    // static DspJitResult JmpR(u16 target_register) {
        // DspJitResult result = DspJitResult(DspJitResultType.JmpR);
        // result.target_register = target_register;
        // return result;
    // }

    static DspJitResult JmpRcc(R32 condition, R32 target_register) {
        DspJitResult result = DspJitResult(DspJitResultType.JmpRcc, condition, target_register);
        return result;
    }

    static DspJitResult RetCc(R32 condition) {
        return DspJitResult(DspJitResultType.RetCc, condition);
    }

    static DspJitResult RtiCc(R32 condition) {
        return DspJitResult(DspJitResultType.RtiCc, condition);
    }
}

final class DspJit {
    DspPageTable page_table;
    CodeBlockTracker codeblocks;
    DspCode code;
    DspMemory dsp_memory;
    DSP dsp_instance;

    this() {
        page_table = new DspPageTable();
        codeblocks = new CodeBlockTracker();
        code       = new DspCode();
        dsp_memory = new DspMemory();
    }

    void set_dsp_instance(DSP dsp) {
        dsp_instance = dsp;
    }

    JitExitReason run(DspState* state) {
        if (state.interrupt_pending) {
            state.handle_interrupt();
        }
        
        u32 jit_compilation_flags = get_jit_compilation_flags(state);
        if (page_table.has(state.pc, jit_compilation_flags)) {
            DspJitEntry entry = page_table.get(state.pc, jit_compilation_flags);
            return execute_compiled_block(entry.func, state);
        } else {
            return compile_and_execute(state, state.pc);
        }
    }

    JitExitReason compile_and_execute(DspState* state, u16 pc) {
        compile(state, pc);
        
        u32 jit_compilation_flags = get_jit_compilation_flags(state);
        DspJitEntry entry = page_table.get(pc, jit_compilation_flags);
        return execute_compiled_block(entry.func, state);
    }

    JitExitReason run_cycles(DspState* state, u32 max_cycles) {
        u32 cycles_executed = 0;
        
        while (cycles_executed < max_cycles) {
            if (state.interrupt_pending) {
                state.handle_interrupt();
                cycles_executed++;
                continue;
            }
            
            u32 jit_compilation_flags = get_jit_compilation_flags(state);
            
            if (!page_table.has(state.pc, jit_compilation_flags)) {
                compile(state, state.pc);
            }
            
            DspJitEntry entry = page_table.get(state.pc, jit_compilation_flags);
            
            if (cycles_executed + entry.instruction_count > max_cycles) {
                break;
            }
            
            u16 old_pc = state.pc;
            
            JitExitReason result = execute_compiled_block(entry.func, state);
            cycles_executed += entry.instruction_count;
            
            if (state.loop_counter > 0) {
                state.loop_counter--;
                if (state.loop_counter > 0) {
                    state.pc = old_pc;
                }
            }
            
            if (result != JitExitReason.BlockEnd) {
                return result;
            }
        }
        
        return JitExitReason.BlockEnd;
    }

    private u32 get_jit_compilation_flags(DspState* state) {
        u32 bitfield = 0;
        return bitfield;
    }

    void invalidate_code_cache() {
        codeblocks = new CodeBlockTracker();
    }

    void invalidate_range(u16 start, u16 end) {
        page_table.invalidate_range(start, end);
    }

    void compile(DspState* state, u16 pc) {
        code.init(state);

        DspEmissionResult emission_result = emit_dsp_block(code, dsp_memory, dsp_instance, pc);
        u8[] bytes = code.get();

        void* executable_code = codeblocks.put(bytes.ptr, bytes.length);
        DspJitFunction func = cast(DspJitFunction) executable_code;
        
        DspJitEntry entry = DspJitEntry(
            func,
            cast(u16) emission_result.instruction_count,
            true
        );
        u32 jit_compilation_flags = get_jit_compilation_flags(state);
        page_table.put(pc, jit_compilation_flags, entry);
    }

    JitExitReason execute_compiled_block(DspJitFunction func, DspState* state) {
            // if (dsp_instance.interrupt_controller.broadway.mem.mmio.ipc.file_manager.usb_dev_57e305.usb_manager.bluetooth.wiimote.button_state & 4) {
        // log_dsp("Executing DSP block at PC=0x%04x", state.pc);
            // }

            // log_dsp("PC=0x%04x AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x] WR=[0x%04x,0x%04x,0x%04x,0x%04x] loop=%d", 
            //         state.pc, state.ar[0], state.ar[1], state.ar[2], state.ar[3],
            //         state.ix[0], state.ix[1], state.ix[2], state.ix[3],
            //         state.wr[0], state.wr[1], state.wr[2], state.wr[3], state.loop_counter);
            // log_dsp("AC0=0x%016x AC1=0x%016x AX0=0x%08x AX1=0x%08x",
            //         state.ac[0].full, state.ac[1].full, state.ax[0].full, state.ax[1].full);
            // log_dsp("Call_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Data_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
            //         state.call_stack.sp, state.call_stack.data[0], state.call_stack.data[1], state.call_stack.data[2], state.call_stack.data[3],
            //         state.data_stack.sp, state.data_stack.data[0], state.data_stack.data[1], state.data_stack.data[2], state.data_stack.data[3]);
            // log_dsp("Loop_Addr_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Loop_Cnt_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
            //         state.loop_address_stack.sp, state.loop_address_stack.data[0], state.loop_address_stack.data[1], state.loop_address_stack.data[2], state.loop_address_stack.data[3],
            //         state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
            // if (state.pc == 0x007d) {
            //     log_dsp("Breakpoint hit at PC=0x%04x", state.pc);
            // }
        u32 result = func(cast(void*) state, cast(void*) dsp_memory);
        check_loop_address(state);
        
            // if (dsp_instance.interrupt_controller.broadway.mem.mmio.ipc.file_manager.usb_dev_57e305.usb_manager.bluetooth.wiimote.button_state & 4) {
        // log_dsp("=== POST-EXECUTION STATE ===");
        // log_dsp("PC=0x%04x AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x]", 
        //         state.pc, state.ar[0], state.ar[1], state.ar[2], state.ar[3],
        //         state.ix[0], state.ix[1], state.ix[2], state.ix[3]);
        // log_dsp("WR=[0x%04x,0x%04x,0x%04x,0x%04x] AC0=0x%016x AC1=0x%016x", 
        //         state.wr[0], state.wr[1], state.wr[2], state.wr[3],
        //         state.ac[0].full, state.ac[1].full);
        // log_dsp("AX0=0x%08x AX1=0x%08x PROD=[0x%04x,0x%04x,0x%04x,0x%04x]",
        //         state.ax[0].full, state.ax[1].full,
        //         state.prod_lo, state.prod_m1, state.prod_m2, state.prod_hi);
        // log_dsp("Call_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Data_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //         state.call_stack.sp, state.call_stack.data[0], state.call_stack.data[1], state.call_stack.data[2], state.call_stack.data[3],
        //         state.data_stack.sp, state.data_stack.data[0], state.data_stack.data[1], state.data_stack.data[2], state.data_stack.data[3]);
        // log_dsp("Loop_Addr_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Loop_Cnt_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //         state.loop_address_stack.sp, state.loop_address_stack.data[0], state.loop_address_stack.data[1], state.loop_address_stack.data[2], state.loop_address_stack.data[3],
        //         state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
        // log_dsp("SR=0x%04x CFG=0x%04x", state.peek_reg(19), state.config);
            // }

        return cast(JitExitReason) result;
    }

    void upload_iram(u16[] iram) {
        dsp_memory.upload_iram(iram);
    }

    // used for tests
    void single_step_until_halt(DspState* state) {
        while (compile_and_execute(state, state.pc) != JitExitReason.DspHalted) {}
    }

    void check_loop_address(DspState* state) {
        if (!state.loop_address_stack.is_empty()) {
            u16 loop_address = state.loop_address_stack.peek();
            // log_dsp("Checking loop address at PC=%x (loop start=%x)", state.pc, loop_address - 1);
            if (state.pc - 1 == loop_address) {
                state.loop_counter_stack.data[state.loop_counter_stack.sp - 1]--;
                if (state.loop_counter_stack.peek() == 0) {
                    state.call_stack.pop();
                    state.loop_address_stack.pop();
                    state.loop_counter_stack.pop();
                } else {
                    // log_dsp("Looping back to address %x, %d iterations remaining", state.call_stack.peek(), state.loop_counter_stack.peek());
                    state.pc = state.call_stack.peek();
                }
            }
        }
    }
}