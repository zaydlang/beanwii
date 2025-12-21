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
import emu.hw.broadway.exception_type;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import std.algorithm;
import std.meta;
import std.stdio;
import util.bitop;
import util.log;
import util.number;
import util.ringbuffer;

alias ReadHandler8  = u32 function(u32 address);
alias ReadHandler16 = u32 function(u32 address);
alias ReadHandler32 = u32 function(u32 address);
alias ReadHandler64 = u64 function(u32 address);
alias WriteHandler8  = void function(u32 address, u8 value);
alias WriteHandler16 = void function(u32 address, u16 value);
alias WriteHandler32 = void function(u32 address, u32 value);
alias WriteHandler64 = void function(u32 address, u64 value);
alias HleHandler   = void function(int param);
alias MfsprHandler = u32 function(GuestReg spr);
alias MtsprHandler = void function(GuestReg spr, u32 value);

struct JitContext {
    u32 pc;
    bool pse;
    bool mmu_enabled;
}

struct JitReturnValue {
    u32 num_instructions_executed;
    BlockReturnValue block_return_value;
}

struct JitConfig {
    ReadHandler8   physical_read_handler8;
    ReadHandler16  physical_read_handler16;
    ReadHandler32  physical_read_handler32;
    ReadHandler64  physical_read_handler64;
    WriteHandler8  physical_write_handler8;
    WriteHandler16 physical_write_handler16;
    WriteHandler32 physical_write_handler32;
    WriteHandler64 physical_write_handler64;
    ReadHandler8   virtual_read_handler8;
    ReadHandler16  virtual_read_handler16;
    ReadHandler32  virtual_read_handler32;
    ReadHandler64  virtual_read_handler64;
    WriteHandler8  virtual_write_handler8;
    WriteHandler16 virtual_write_handler16;
    WriteHandler32 virtual_write_handler32;
    WriteHandler64 virtual_write_handler64;
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

__gshared Jit g_jit;

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
    
    public  Mem mem;
    private PageTable!JitEntry code_page_table;
    private PageTable!(BasicBlockLinkRequest[]) basic_block_link_requests;
    private DebugRing debug_ring;
    public  Code code;
    
    u64 total_instructions_executed = 0;
    u64 total_jit_exits = 0;
    u64[8] exit_reason_histogram = 0;
    u64 total_patches_applied = 0;
    u64 total_patch_requests_submitted = 0;
    u64 total_patch_requests_processed = 0;
    u64 patches_failed_child_not_found = 0;
    u64 patches_failed_id_mismatch = 0;

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
        this.idle_loop_detector = new IdleLoopDetector(mem);
        this.breakpoints = [];
        g_jit = this;
    }

    int dick = 0;

    BlockReturnValue process_jit_function(JitFunction func, BroadwayState* state) {
        state.cycle_quota = 0;

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
            
            case BlockReturnValue.PatchableBranchTaken:
                break;
            
            case BlockReturnValue.UnpatchableBranchTaken:
                break;
            
            case BlockReturnValue.DecrementerChanged:
                break;
            
            case BlockReturnValue.IdleLoopDetected:
                break;
            
            case BlockReturnValue.FloatingPointUnavailable:
                break;
            
            default:
                break;
        }

        return ret;
    }

    // returns the number of instructions executed
    pragma(inline, true) public JitReturnValue run(BroadwayState* state) {
        u32 jit_key = create_jit_key(state);

        JitReturnValue ret;
        if (code_page_table.has(jit_key)) {
            JitEntry* entry = code_page_table.get_assume_has(jit_key);
            entry.num_times_executed++;
            ret = JitReturnValue(state.cycle_quota, process_jit_function(entry.func, state));
        } else {
            code.init();
            auto num_instructions = cast(int) emit(this, code, mem, state.pc, get_mmu_enabled(state));
            u8[] bytes = code.get();
            auto ptr = codeblocks.put(bytes.ptr, bytes.length);
            
            auto func = cast(JitFunction) ptr;            
            code_page_table.put(jit_key, JitEntry(func, generate_new_jit_id(), cast(int) bytes.length, num_instructions, 1));
            process_basic_block_link_requests_for_parent(jit_key);

            ret = JitReturnValue(state.cycle_quota, process_jit_function(func, state));
        }
        
        total_instructions_executed += ret.num_instructions_executed;
        total_jit_exits++;
        // exit_reason_histogram[ret.block_return_value.value()]++;
        
        return ret;
    }

    private bool get_mmu_enabled(BroadwayState* state) {
        return state.msr.bits(4, 5) == 0b11;
    }

    private u32 create_jit_key(BroadwayState* state) {
        u32 key = state.pc;
        bool mmu_enabled = get_mmu_enabled(state);
        
        key |= (mmu_enabled ? 1 : 0) << 27;
        
        return key;
    }

    public u32 create_jit_key_from_address(u32 address, bool mmu_enabled) {
        u32 key = address;
        key |= (mmu_enabled ? 1 : 0) << 27;
        return key;
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

    u64 get_address_for_code(u32 address, bool mmu_enabled) {
        u32 jit_key = address | (mmu_enabled ? (1 << 27) : 0);
        return cast(u64) code_page_table.get_assume_has(jit_key).func;
    }

    bool has_code_for(u32 address, bool mmu_enabled) {
        u32 jit_key = address | (mmu_enabled ? (1 << 27) : 0);
        return code_page_table.has(jit_key);
    }

    void add_dependent(u32 parent_key, u32 child_key) {
        log_jit("Adding dependency: parent=0x%08x -> child=0x%08x", parent_key, child_key);
        auto list = parent_key in dependents;

        if (list is null) {
            log_jit("Creating new dependency list for parent=0x%08x", parent_key);
            dependents[parent_key] = [child_key];
        } else {
            log_jit("Appending to existing dependency list for parent=0x%08x (current size: %d)", parent_key, (*list).length);
            dependents[parent_key] ~= child_key;
        }
    }

    void invalidate(u32 address) {
        log_jit("Invalidating block at 0x%08x", address);
        
        basic_block_link_requests.remove(address);
        
        code.clear_slow_access(address);

        u32 key_mmu_off = address;
        u32 key_mmu_on = address | (1 << 27);
        
        invalidate_key(key_mmu_off);
        invalidate_key(key_mmu_on);
    }

    void invalidate_no_clear_slowmem(u32 address) {
        log_jit("Invalidating block at 0x%08x without clearing slowmem", address);
        
        basic_block_link_requests.remove(address);

        u32 key_mmu_off = address;
        u32 key_mmu_on = address | (1 << 27);
        
        invalidate_key(key_mmu_off);
        invalidate_key(key_mmu_on);
    }

    void invalidate_key(u32 jit_key) {
        if (code_page_table.has(jit_key)) {
            log_jit("Block exists in page table (key=0x%08x), removing and invalidating dependents", jit_key);
            code_page_table.remove(jit_key);

            if (jit_key in dependents) {
                log_jit("Found %d dependents for block 0x%08x", dependents[jit_key].length, jit_key);
                foreach (dependent_key; dependents[jit_key]) {
                    log_jit("Recursively invalidating dependent 0x%08x", dependent_key);
                    invalidate_key(dependent_key);
                }
                dependents.remove(jit_key);
            }
        }
    }

    int x = 0;
    void submit_basic_block_link_patch_point(u32 parent, u32 child, u64 patch_point_offset) {
        log_jit("Submitting link request: parent=0x%08x child=0x%08x offset=0x%016x", parent, child, patch_point_offset);
        basic_block_link_requests.put(parent, [BasicBlockLinkRequest(patch_point_offset, child, 0, peek_next_jit_id(), mem.cpu.scheduler.get_current_time())]);
        total_patch_requests_submitted++;
    }

    void process_basic_block_link_requests_for_parent(u32 parent) {
        if (!basic_block_link_requests.has(parent)) {
            log_jit("No link requests for parent 0x%08x", parent);
            return;
        }
        
        auto requests = basic_block_link_requests.get_assume_has(parent);
        log_jit("Processing %d link requests for parent 0x%08x", requests.length, parent);

        foreach (request; *requests) {
            log_jit("Processing request: child=0x%08x offset=0x%016x id=%d", request.child, request.patch_point_offset, request.id);
            total_patch_requests_processed++;
            
            if (!code_page_table.has(request.child)) {
                log_jit("Child block 0x%08x not found in page table, skipping", request.child);
                patches_failed_child_not_found++;
                continue;
            }

            auto child_entry = code_page_table.get_assume_has(request.child);
            if (request.id != child_entry.id) {
                log_jit("ID mismatch for child 0x%08x: request_id=%d child_id=%d, skipping", request.child, request.id, child_entry.id);
                patches_failed_id_mismatch++;
                continue;
            }

            auto parent_entry = code_page_table.get_assume_has(parent);

            auto patch_point_offset = child_entry.func_size - 48;
            u64 func = cast(u64) parent_entry.func + 15;
            u8* patch_point = cast(u8*) (cast(u64) child_entry.func + patch_point_offset);

            log_jit("Patching at offset 0x%016x in child func 0x%016x, jumping to parent func 0x%016x", 
                   patch_point_offset, cast(u64) child_entry.func, func);

            for (int i = 0; i < 25; i++) {
                if (patch_point[i] != 0x90) {
                    error_jit("Patch point %x at index %d is not nop. Dumping stuff: %x %s %x %s %s", patch_point[i], i, parent, child_entry, patch_point_offset, request, basic_block_link_requests.get_assume_has(parent));
                }
            }

            log_jit("Writing patch code to link blocks");
            
            // cmpl state.cycle_quota, 0x00e8
            patch_point[0] = 0x81;
            patch_point[1] = 0xbf;
            patch_point[2] = 0xe6;
            patch_point[3] = 0x03;
            patch_point[4] = 0x00;
            patch_point[5] = 0x00;
            patch_point[6] = 0xe8;
            patch_point[7] = 0x00;
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
            total_patches_applied++;
            log_jit("Successfully linked child 0x%08x to parent 0x%08x", request.child, parent);
        }
        
        basic_block_link_requests.remove(parent);
        log_jit("Removed all link requests for parent 0x%08x", parent);
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

    void dump_all_entries() {
        // Collect all entries with their addresses and execution counts
        struct EntryInfo {
            u32 address;
            int num_times_executed;
            u32 num_instructions;
            u64 id;
            int func_size;
        }
        
        EntryInfo[] entries;
        
        code_page_table.iterate_all((u32 address, JitEntry entry) {
            entries ~= EntryInfo(address, entry.num_times_executed, 
                                entry.num_instructions, entry.id, entry.func_size);
        });
        
        entries.sort!((a, b) => a.num_times_executed < b.num_times_executed);
        
        writeln("=== JIT Entries Dump (sorted by execution count ascending) ===");
        writefln("Total entries: %d", entries.length);
        writeln("Address    | Exec Count | Instructions | ID       | Func Size");
        writeln("-----------|------------|--------------|----------|----------");
        
        foreach (entry; entries) {
            writefln("0x%08X | %10d | %12d | %8d | %9d", 
                    entry.address, entry.num_times_executed, 
                    entry.num_instructions, entry.id, entry.func_size);
        }
        
        writeln("=== End JIT Dump ===");
        print_instruction_stats();
        
        // Dump guest stack
        writeln("=== Guest Stack Dump ===");
        auto broadway = cast(Broadway) mem.cpu;
        if (broadway) {
            broadway.dump_stack();
        }
    }
    
    public double get_average_instructions_per_exit() {
        if (total_jit_exits == 0) return 0.0;
        return cast(double) total_instructions_executed / cast(double) total_jit_exits;
    }
    
    public void print_instruction_stats() {
        writefln("Total instructions executed: %d", total_instructions_executed);
        writefln("Total JIT exits: %d", total_jit_exits);
        writefln("Average instructions per JIT exit: %.2f", get_average_instructions_per_exit());
        writefln("Total patches applied: %d", total_patches_applied);
        writefln("Total patch requests submitted: %d", total_patch_requests_submitted);
        writefln("Total patch requests processed: %d", total_patch_requests_processed);
        writefln("Patches failed - child not found: %d", patches_failed_child_not_found);
        writefln("Patches failed - ID mismatch: %d", patches_failed_id_mismatch);
        writeln("Exit reason histogram:");
        
        for (int i = 0; i < exit_reason_histogram.length; i++) {
            if (exit_reason_histogram[i] > 0) {
                double percentage = (cast(double)exit_reason_histogram[i] / cast(double)total_jit_exits) * 100.0;
                writefln("  %s: %d (%.2f%%)", cast(BlockReturnValue)i, exit_reason_histogram[i], percentage);
            }
        }
    }
}