module emu.hw.broadway.jit.jit;

import capstone;
import core.sys.posix.sys.mman;
import dklib.khash;
import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.idle_loop_detector;
import emu.hw.broadway.jit.emission.return_value;
import emu.hw.broadway.jit.page_table;
import emu.hw.broadway.cpu;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import std.meta;
import util.bitop;
import util.log;
import util.number;
import util.ringbuffer;

alias ReadHandler  = u32 function(u32 address);
alias WriteHandler = void function(u32 address, u32 value);
alias HleHandler   = void function(int param);
alias MfsprHandler = u32 function(GuestReg spr);
alias MtsprHandler = void function(GuestReg spr, u32 value);

struct JitContext {
    u32 pc;
    bool pse;
}

struct JitReturnValue {
    u32 num_instructions_executed;
    BlockReturnValue block_return_value;
}

struct JitConfig {
    ReadHandler  read_handler8;
    ReadHandler  read_handler16;
    ReadHandler  read_handler32;
    ReadHandler  read_handler64;
    WriteHandler write_handler8;
    WriteHandler write_handler16;
    WriteHandler write_handler32;
    WriteHandler write_handler64;
    HleHandler   hle_handler;
    MfsprHandler read_spr_handler;
    MtsprHandler write_spr_handler;

    void*        mem_handler_context;
    void*        hle_handler_context;
    void*        spr_handler_context;
}

private alias JitFunction = BlockReturnValue function(BroadwayState* state);

struct JitEntry {
    JitFunction func;
    u64         id;
    int         func_size;
    u32         num_instructions;
    int         num_times_executed;
}

final class Jit {
    private struct DebugState {
        BroadwayState state;
        u32 instruction;
    }

    private struct BasicBlockLinkRequest {
        u64 patch_point_offset;
        u32 child;
        u32 padding;
        u64 id;
        u64 timestamp;
    }

    private alias DebugRing  = RingBuffer!(DebugState);
    
    private Mem mem;
    private PageTable!JitEntry code_page_table;
    private PageTable!(BasicBlockLinkRequest[]) basic_block_link_requests;
    private DebugRing debug_ring;
    private Code code;

    private CodeBlockTracker codeblocks;
    public  IdleLoopDetector idle_loop_detector;

    u32[][u32] dependents;

    this(JitConfig config, Mem mem, int ringbuffer_size) {
        this.mem = mem;
        this.code_page_table = new PageTable!JitEntry();
        this.basic_block_link_requests = new PageTable!(BasicBlockLinkRequest[]);
        this.debug_ring = new DebugRing(ringbuffer_size);
        this.code = new Code(config);
        this.codeblocks = new CodeBlockTracker();
        this.idle_loop_detector = new IdleLoopDetector();
        this.breakpoints = [];
    }

    int dick = 0;

    BlockReturnValue process_jit_function(JitFunction func, BroadwayState* state) {
        state.cycle_quota = 0;
        // log_state(state);
        if (state.pc == 0x800653c4) {
            // log_wii("JIT: %x %x %x", state.pc, 0,0);
        }


        BlockReturnValue ret = func(state);

        switch (ret.value) {
            case BlockReturnValue.ICacheInvalidation: {
                state.icbi_address &= ~31;
                
                for (u32 i = 0; i < 32 + code.get_max_instructions_per_block() - 1; i += 4) {
                    invalidate(state.icbi_address + i - code.get_max_instructions_per_block() + 1);
                }

                break;
            }

            case BlockReturnValue.GuestBlockEnd:
                break;

            case BlockReturnValue.CpuHalted:
                // error_jit("CPU halted");
                break;
            
            case BlockReturnValue.BranchTaken:
                break;
            
            case BlockReturnValue.DecrementerChanged:
                break;
            
            case BlockReturnValue.IdleLoopDetected:
                break;
            
            default:
                break;
        }

        return ret;
    }

    // returns the number of instructions executed
    public JitReturnValue run(BroadwayState* state) {
        log_jit("JIT: Running block at %x", state.pc);
        if (code_page_table.has(state.pc)) {
            JitEntry entry = code_page_table.get_assume_has(state.pc);
            entry.num_times_executed++;
            return JitReturnValue(state.cycle_quota, process_jit_function(entry.func, state));
        } else {
            code.init();
            auto num_instructions = cast(int) emit(this, code, mem, state.pc);
            u8[] bytes = code.get();
            auto ptr = codeblocks.put(bytes.ptr, bytes.length);
            
            auto func = cast(JitFunction) ptr;            
            code_page_table.put(state.pc, JitEntry(func, generate_new_jit_id(), cast(int) bytes.length, num_instructions, 1));
            process_basic_block_link_requests_for_parent(state.pc);

            return JitReturnValue(state.cycle_quota, process_jit_function(func, state));
        }
    }

    private void log_instruction(u32 instruction, u32 pc) {
        auto x86_capstone = create(Arch.ppc, ModeFlags(Mode.bit64));
        auto res = x86_capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);
        foreach (instr; res) {
            log_broadway("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
        }
    }

    public void on_error() {
        // this.dump_debug_ring();
    }

    private void dump_debug_ring() {
        foreach (debug_state; this.debug_ring.get()) {
            log_instruction(debug_state.instruction, debug_state.state.pc - 4);
            log_state(&debug_state.state);
        }
    }

    u64 get_address_for_code(u32 address) {
        return cast(u64) code_page_table.get_assume_has(address).func;
    }

    bool has_code_for(u32 address) {
        return code_page_table.has(address);
    }

    void add_dependent(u32 parent, u32 child) {
        auto list = parent in dependents;

        if (list !is null) {
            dependents[parent] = [child];
        } else {
            dependents[parent] ~= child;
        }
    }

    void invalidate(u32 address) {
        // log_jit("Invalidating %x", address);
        
        basic_block_link_requests.remove(address);

        if (code_page_table.has(address)) {
            code_page_table.remove(address);

            if (address in dependents) {
                foreach (dependent; dependents[address]) {
                    invalidate(dependent);
                }
            }
        }
    }

    int x = 0;
    void submit_basic_block_link_patch_point(u32 parent, u32 child, u64 patch_point_offset) {
        basic_block_link_requests.put(parent, [BasicBlockLinkRequest(patch_point_offset, child, 0, peek_next_jit_id(), mem.cpu.scheduler.get_current_time())]);
    }

    void process_basic_block_link_requests_for_parent(u32 parent) {
        if (!basic_block_link_requests.has(parent)) {
            return;
        }
        // log_jit("basic_block_link_requests.get_assume_has(parent): %s", basic_block_link_requests.get_assume_has(parent));

        foreach (request; basic_block_link_requests.get_assume_has(parent)) {
            if (!code_page_table.has(request.child)) {
                continue;
            }

            auto child_entry = code_page_table.get_assume_has(request.child);
            if (request.id != child_entry.id) {
                continue;
            }

            auto parent_entry = code_page_table.get_assume_has(parent);

            auto patch_point_offset = child_entry.func_size - 48;
            u64 func = cast(u64) parent_entry.func + 15;
            u8* patch_point = cast(u8*) (cast(u64) child_entry.func + patch_point_offset);

            for (int i = 0; i < 25; i++) {
                if (patch_point[i] != 0x90) {
                    error_jit("Patch point %x at index %d is not nop. Dumping stuff: %x %s %x %s %s", patch_point[i], i, parent, child_entry, patch_point_offset, request, basic_block_link_requests.get_assume_has(parent));
                }
            }

            // cmpl state.cycle_quota, 1000
            patch_point[0] = 0x81;
            patch_point[1] = 0xbf;
            patch_point[2] = 0xda;
            patch_point[3] = 0x03;
            patch_point[4] = 0x00;
            patch_point[5] = 0x00;
            patch_point[6] = 0xe8;
            patch_point[7] = 0x03;
            patch_point[8] = 0x00;
            patch_point[9] = 0x00;

            // jge +0xd
            patch_point[10] = 0x7d;
            patch_point[11] = 0x0d;

            // movabs rax, jump_point
            patch_point[12] = 0x48;
            patch_point[13] = 0xb8;
            patch_point[14] = func.get_byte(0);
            patch_point[15] = func.get_byte(1);
            patch_point[16] = func.get_byte(2);
            patch_point[17] = func.get_byte(3);
            patch_point[18] = func.get_byte(4);
            patch_point[19] = func.get_byte(5);
            patch_point[20] = func.get_byte(6);
            patch_point[21] = func.get_byte(7);

            // jmp rax
            patch_point[22] = 0x48;
            patch_point[23] = 0xff;
            patch_point[24] = 0xe0;

            add_dependent(parent, request.child);
        }
        
        basic_block_link_requests.remove(parent);
    }

    u64 jit_id;
    u64 generate_new_jit_id() {
        return jit_id++;
    }

    u64 peek_next_jit_id() {
        return jit_id;
    }

    void enter_single_step_mode() {
        code.enter_single_step_mode();
        invalidate_all();
    }

    void exit_single_step_mode() {
        code.exit_single_step_mode();
        invalidate_all();
    }

    void invalidate_all() {
        code_page_table = new PageTable!JitEntry();
        basic_block_link_requests = new PageTable!(BasicBlockLinkRequest[]);
        codeblocks = new CodeBlockTracker();
    }

    u32[] breakpoints;
    void add_breakpoint(u32 address) {
        breakpoints ~= address;

        // compilation is really fast, and if im in a debugger i don't care about
        // performance anyway. lets do something thats definitely correct.
        invalidate_all(); 
    }

    bool has_breakpoint(u32 address) {
        foreach (breakpoint; breakpoints) {
            if (address == breakpoint) {
                return true;
            }
        }

        return false;
    }
}