module emu.hw.dsp.jit.jit;

import emu.hw.dsp.jit.page_table;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.emission.emit;
import emu.hw.dsp.jit.emission.idle_loop_detector;
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
    IdleLoopDetected = 3,
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
    BLoop     = 13,
    BLoopi    = 14,
    Loop      = 15,
    Loopi     = 16,
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

    static DspJitResult CallRcc(R32 condition, R32 target_register) {
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

    static DspJitResult BLoop() {
        return DspJitResult(DspJitResultType.BLoop);
    }

    static DspJitResult BLoopi() {
        return DspJitResult(DspJitResultType.BLoopi);
    }

    static DspJitResult Loop() {
        return DspJitResult(DspJitResultType.Loop);
    }

    static DspJitResult Loopi() {
        return DspJitResult(DspJitResultType.Loopi);
    }
}

struct DspPcEntry {
    u16 pc;
    u16 instruction;
}

final class DspJit {
    DspPageTable page_table;
    CodeBlockTracker codeblocks;
    DspCode code;
    DspMemory dsp_memory;
    DSP dsp_instance;
    DspIdleLoopDetector idle_loop_detector;
    
    // PC execution history ringbuffer
    DspPcEntry[256] pc_history;
    u8 pc_history_index = 0;
    
    void print_pc_history() {
        import std.stdio;
        writefln("=== DSP PC Execution History (last 256 entries) ===");
        for (int i = 0; i < 256; i++) {
            u8 idx = cast(u8)((pc_history_index + i) % 256);
            if (pc_history[idx].pc != 0) {
                writefln("[%3d] PC=0x%04X instruction=0x%04X", i, pc_history[idx].pc, pc_history[idx].instruction);
            }
        }
        writefln("=== End PC History ===");
    }

    this() {
        page_table = new DspPageTable();
        codeblocks = new CodeBlockTracker();
        code       = new DspCode();
        dsp_memory = new DspMemory();
        idle_loop_detector = new DspIdleLoopDetector();
    }

    void set_dsp_instance(DSP dsp) {
        dsp_instance = dsp;
    }

    JitExitReason compile_and_execute(DspState* state, u16 pc) {
        compile(state, pc);
        
        u8 max_block_size = calculate_max_block_size(state, state.pc);
        u32 jit_compilation_flags = get_jit_compilation_flags(state, max_block_size);
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
            
            u8 max_block_size = calculate_max_block_size(state, state.pc);
            u32 jit_compilation_flags = get_jit_compilation_flags(state, max_block_size);
            
            if (!page_table.has(state.pc, jit_compilation_flags)) {
                compile(state, state.pc);
            }
            
            DspJitEntry entry = page_table.get(state.pc, jit_compilation_flags);
            
            if (cycles_executed + entry.instruction_count > max_cycles) {
                break;
            }
            
            bool in_loop = state.loop_counter > 0;
            u16 old_pc = state.pc;
            
            JitExitReason result = execute_compiled_block(entry.func, state);
            cycles_executed += entry.instruction_count;

            if (in_loop) {
                // writefln("Decrementing loop counter from %d %x", state.loop_counter, state.pc);
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

    private u8 calculate_max_block_size(DspState* state, u16 pc) {
        // if (state.pc >= 0x0e6d && state.pc <= 0x0ee8) {
        if ((state.pc >= 0x0d99 && state.pc <= 0xdb0)) {
        // if ((state.pc >= 0x07c3 && state.pc <= 0x07da) || (state.pc >= 0x0e6d && state.pc <= 0x0ee8)) {
            // return 1;
        }

        if (state.loop_counter > 0) {
            return 1; // In a loop, force single instruction blocks
        }
        
        if (state.loop_address_stack.is_empty()) {
            return 32; // No active loop, use full block size
        }
        
        u16 loop_address = state.loop_address_stack.peek();
        if (loop_address < pc) {
            return 32; // Loop target is behind us
        }
        
        u16 distance_to_loop = cast(u16) (loop_address - pc + 1);
        if (distance_to_loop >= 32) {
            return 32; // Loop is far away, use full block size
        }
        
        return cast(u8) distance_to_loop; // Limit block size to stay within loop
    }

    private u32 get_jit_compilation_flags(DspState* state, u8 max_block_size) {
        u32 bitfield = 0;
        bitfield |= cast(u32) max_block_size;
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

        u8 max_block_size = calculate_max_block_size(state, pc);
        DspEmissionResult emission_result = emit_dsp_block(code, dsp_memory, dsp_instance, pc, max_block_size, idle_loop_detector);
        u8[] bytes = code.get();

        void* executable_code = codeblocks.put(bytes.ptr, bytes.length);
        DspJitFunction func = cast(DspJitFunction) executable_code;
        
        DspJitEntry entry = DspJitEntry(
            func,
            cast(u16) emission_result.instruction_count,
            true
        );
        u32 jit_compilation_flags = get_jit_compilation_flags(state, max_block_size);
        page_table.put(pc, jit_compilation_flags, entry);
    }

    u16 camefrom = 0;
    bool after = false;
    JitExitReason execute_compiled_block(DspJitFunction func, DspState* state) {
        // import std.stdio;
        // writefln("Executing DSP block at PC=0x%04x", state.pc);
        // writefln("PC=0x%04x AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x] WR=[0x%04x,0x%04x,0x%04x,0x%04x] loop=%d", 
        //         state.pc, state.ar[0], state.ar[1], state.ar[2], state.ar[3],
        //         state.ix[0], state.ix[1], state.ix[2], state.ix[3],
        //         state.wr[0], state.wr[1], state.wr[2], state.wr[3], state.loop_counter);
        // writefln("AX0=0x%08x AX1=0x%08x PROD=[0x%04x,0x%04x,0x%04x,0x%04x]",
        //         state.ax[0].full, state.ax[1].full,
        //         state.prod_lo, state.prod_m1, state.prod_m2, state.prod_hi);
        // writefln("AC0=0x%016x AC1=0x%016x",
        //         state.ac[0].full, state.ac[1].full);
        // writefln("Call_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Data_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //         state.call_stack.sp, state.call_stack.data[0], state.call_stack.data[1], state.call_stack.data[2], state.call_stack.data[3],
        //         state.data_stack.sp, state.data_stack.data[0], state.data_stack.data[1], state.data_stack.data[2], state.data_stack.data[3]);
        // writefln("Loop_Addr_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Loop_Cnt_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //         state.loop_address_stack.sp, state.loop_address_stack.data[0], state.loop_address_stack.data[1], state.loop_address_stack.data[2], state.loop_address_stack.data[3],
        //         state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
        // writefln("SR: 0x%04x", state.peek_reg(19));

            

        u16 bb2_before = dsp_memory.read_data(0x2b2);
        u8 call_stack_sp_before = state.call_stack.sp;
        u16 pc_start = state.pc;
        u16 wr3_before = state.wr[3];
        camefrom = state.pc;
        
        if (state.pc == 0x0e3a) {
            writefln("PC: 0x%04x camefrom=0x%04x", state.pc, camefrom);
            writefln("PC: 0x%04x camefrom=0x%04x", state.pc, camefrom);
            writefln("PC: 0x%04x camefrom=0x%04x", state.pc, camefrom);
            writefln("PC: 0x%04x camefrom=0x%04x", state.pc, camefrom);
        }

        u32 result = func(cast(void*) state, cast(void*) dsp_memory);
        check_loop_address(state);
        u8 call_stack_sp_after = state.call_stack.sp;
        u16 pc_end = state.pc;
        u16 wr3_after = state.wr[3];
        u16 b2b2_after = dsp_memory.read_data(0x2b2);

        // if (bb2_before != b2b2_after || state.pc == 0x7c3) {
        //     import std.stdio;
        //     writefln("2B2 changed: 0x%04X -> 0x%04X (PC=0x%04X)", bb2_before, b2b2_after, state.pc);

        //     writefln("camefrom=0x%04x after=%s", camefrom, after ? "true" : "false");
        //     writefln("PC=0x%04x AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x] WR=[0x%04x,0x%04x,0x%04x,0x%04x] loop=%d", 
        //             state.pc, state.ar[0], state.ar[1], state.ar[2], state.ar[3],
        //             state.ix[0], state.ix[1], state.ix[2], state.ix[3],
        //             state.wr[0], state.wr[1], state.wr[2], state.wr[3], state.loop_counter);
        //     writefln("AX0=0x%08x AX1=0x%08x PROD=[0x%04x,0x%04x,0x%04x,0x%04x]",
        //             state.ax[0].full, state.ax[1].full,
        //             state.prod_lo, state.prod_m1, state.prod_m2, state.prod_hi);
        //     writefln("SR: 0x%04x", state.peek_reg(19));
        //     writefln("PC: 0x%04x", state.pc);
        //     writefln("instruction: 0x%04x %s", dsp_memory.read_instruction(state.pc), decode_instruction_with_extension(dsp_memory.read_instruction(state.pc), dsp_memory.read_instruction(cast(u16) (state.pc + 1))));
        //     writefln("AC0=0x%016x AC1=0x%016x AX0=0x%08x AX1=0x%08x",
        //             state.ac[0].full, state.ac[1].full, state.ax[0].full, state.ax[1].full);
        //     writefln("Call_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Data_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //             state.call_stack.sp, state.call_stack.data[0], state.call_stack.data[1], state.call_stack.data[2], state.call_stack.data[3],
        //             state.data_stack.sp, state.data_stack.data[0], state.data_stack.data[1], state.data_stack.data[2], state.data_stack.data[3]);
        //     writefln("Loop_Addr_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Loop_Cnt_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //             state.loop_address_stack.sp, state.loop_address_stack.data[0], state.loop_address_stack.data[1], state.loop_address_stack.data[2], state.loop_address_stack.data[3],
        //             state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
        //     writefln("Loop Counter Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
        //             state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
        // }
        
        if (wr3_before != wr3_after) {
            import std.stdio;
            // writefln("WR3 changed: 0x%04X -> 0x%04X (PC=0x%04X)", wr3_before, wr3_after, state.pc);
        }
        

        if (state.pc == 0x74b) {
            // dump ar1..-0x60 to ar
            for (int i = 0; i < 0x60; i++) {
                u16 addr = cast(u16) (state.ar[1] - i - 1);
                u16 value = dsp_memory.read_data(addr);
                // writefln("Data[0x%04x] = 0x%04x", addr, value);
            }
        }

        // if (pc_start < pc_end && (state.pc == 0x0738 || state.pc == 0x0740)) {
            if (dsp_instance.interrupt_controller.broadway.mem.mmio.ipc.file_manager.usb_dev_57e305.usb_manager.bluetooth.wiimote.button_state & 4) {
        // if ((state.pc >= 0x0d99 && state.pc <= 0xdb0)) {
            // after = state.pc == 0x03a1;
            writefln("camefrom=0x%04x after=%s", camefrom, after ? "true" : "false");
            writefln("PC=0x%04x AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x] WR=[0x%04x,0x%04x,0x%04x,0x%04x] loop=%d", 
                    state.pc, state.ar[0], state.ar[1], state.ar[2], state.ar[3],
                    state.ix[0], state.ix[1], state.ix[2], state.ix[3],
                    state.wr[0], state.wr[1], state.wr[2], state.wr[3], state.loop_counter);
            writefln("AX0=0x%08x AX1=0x%08x PROD=[0x%04x,0x%04x,0x%04x,0x%04x]",
                    state.ax[0].full, state.ax[1].full,
                    state.prod_lo, state.prod_m1, state.prod_m2, state.prod_hi);
            writefln("SR: 0x%04x", state.peek_reg(19));
            writefln("PC: 0x%04x", state.pc);
            writefln("instruction: 0x%04x %s", dsp_memory.read_instruction(state.pc), decode_instruction_with_extension(dsp_memory.read_instruction(state.pc), dsp_memory.read_instruction(cast(u16) (state.pc + 1))));
            writefln("AC0=0x%016x AC1=0x%016x AX0=0x%08x AX1=0x%08x",
                    state.ac[0].full, state.ac[1].full, state.ax[0].full, state.ax[1].full);
            writefln("Call_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Data_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
                    state.call_stack.sp, state.call_stack.data[0], state.call_stack.data[1], state.call_stack.data[2], state.call_stack.data[3],
                    state.data_stack.sp, state.data_stack.data[0], state.data_stack.data[1], state.data_stack.data[2], state.data_stack.data[3]);
            writefln("Loop_Addr_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x] Loop_Cnt_Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
                    state.loop_address_stack.sp, state.loop_address_stack.data[0], state.loop_address_stack.data[1], state.loop_address_stack.data[2], state.loop_address_stack.data[3],
                    state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
            writefln("Loop Counter Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]",
                    state.loop_counter_stack.sp, state.loop_counter_stack.data[0], state.loop_counter_stack.data[1], state.loop_counter_stack.data[2], state.loop_counter_stack.data[3]);
        }
        // if (call_stack_sp_before != call_stack_sp_after) {
        //     writefln("Call stack pointer changed: %d -> %d at PC range 0x%04x-0x%04x", call_stack_sp_before, call_stack_sp_after, pc_start, pc_end);
        // }
        // if (cdf_before != dsp_memory.read_data(0xcdf)) {
            
        //         writefln("Stored %x to 0cdf at %x", dsp_memory.read_data(0xcdf), state.pc);
        //     }
        
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
            // writefln("Checking loop address at PC=%x (loop start=%x)", state.pc, loop_address - 1);
            if (state.pc - 1 == loop_address) {

                state.loop_counter_stack.data[state.loop_counter_stack.sp - 1]--;
                if (state.loop_counter_stack.peek() == 0) {
                    state.call_stack.pop();
                    state.loop_address_stack.pop();
                    state.loop_counter_stack.pop();
                } else {
                    // writefln("Looping back to address %x, %d iterations remaining", state.call_stack.peek(), state.loop_counter_stack.peek());
                    state.pc = state.call_stack.peek();
                }
            }
        }
    }
}