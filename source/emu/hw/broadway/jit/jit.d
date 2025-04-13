module emu.hw.broadway.jit.jit;

import capstone;
import core.sys.posix.sys.mman;
import dklib.khash;
import emu.hw.broadway.jit.code_page_table;
import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.return_value;
import emu.hw.broadway.cpu;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import std.meta;
import util.bitop;
import util.log;
import util.number;
import util.ringbuffer;
import xbyak;

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
    u32         num_instructions;
    int         num_times_executed;
}

final class Jit {
    private struct DebugState {
        BroadwayState state;
        u32 instruction;
    }

    private alias DebugRing  = RingBuffer!(DebugState);
    
    private Mem mem;
    private CodePageTable code_page_table;
    private DebugRing debug_ring;
    private Code code;

    private CodeBlockTracker codeblocks;

    u32[][u32] dependents;

    this(JitConfig config, Mem mem, size_t ringbuffer_size) {
        this.mem = mem;
        this.code_page_table = new CodePageTable();
        this.debug_ring = new DebugRing(ringbuffer_size);
        this.code = new Code(config);
        this.codeblocks = new CodeBlockTracker();
    }

    BlockReturnValue process_jit_function(JitFunction func, BroadwayState* state) {
        state.cycle_quota = 0;
        BlockReturnValue ret = func(state);

        switch (ret) {
            case BlockReturnValue.ICacheInvalidation: {
                state.icbi_address &= ~31;
                
                for (u32 i = 0; i < 32 + MAX_GUEST_OPCODES_PER_RECIPE - 1; i += 4) {
                    code_page_table.remove(state.icbi_address + i + MAX_GUEST_OPCODES_PER_RECIPE - 1);
                }

                break;
            }

            case BlockReturnValue.GuestBlockEnd:
                break;

            case BlockReturnValue.CpuHalted:
                break;
            
            case BlockReturnValue.BranchTaken:
                break;
            
            case BlockReturnValue.DecrementerChanged:
                break;
            
            default:
                break;
        }

        return ret;
    }

    // returns the number of instructions executed
    public JitReturnValue run(BroadwayState* state) {
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
            code_page_table.put(state.pc, JitEntry(func, num_instructions, 1));
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
        if (parent !in dependents) {
            dependents[parent] = new u32[0];
        }

        dependents[parent] ~= child;
    }

    void invalidate(u32 address) {
        code_page_table.remove(address);

        if (address in dependents) {
            foreach (dependent; dependents[address]) {
                invalidate(dependent);
            }
        }
    }
}