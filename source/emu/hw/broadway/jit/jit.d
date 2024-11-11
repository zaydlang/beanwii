module emu.hw.broadway.jit.jit;

import capstone;
import dklib.khash;
import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.emit;
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

struct JitContext {
    u32 pc;
    bool pse;
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

    void*        mem_handler_context;
    void*        hle_handler_context;
}

final class Jit {
    private struct DebugState {
        BroadwayState state;
        u32 instruction;
    }

    private alias JitFunction = void function(BroadwayState* state);
    private alias JitHashMap = khash!(u32, JitFunction);
    private alias DebugRing  = RingBuffer!(DebugState);
    
    private Mem        mem;
    private JitHashMap jit_hash_map;
    private DebugRing  debug_ring;
    private Code       code;

    this(JitConfig config, Mem mem, size_t ringbuffer_size) {
        this.mem = mem;
        this.jit_hash_map = JitHashMap();
        this.debug_ring = new DebugRing(ringbuffer_size);
        this.code = new Code(config);
    }

    // returns the number of instructions executed
    public u32 run(BroadwayState* state) {
        if (code.init()) {
            this.jit_hash_map = JitHashMap();
        }        

        auto cached_func = jit_hash_map.require(state.pc, null);
        if (cached_func != null) {
            cached_func(state);
        } else {
            emit(code, mem, state.pc);
            log_state(state);
            auto func = code.get_function!JitFunction();
            // jit_hash_map[state.pc] = func;

            //     auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
            //     auto res = x86_capstone.disasm((cast(ubyte*) func)[0 .. code.getSize()], 0);
            //     foreach (instr; res) {
            //         // log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
            //     }

        if (mem.read_be_u32(state.pc) == 0x4d820020) {
            int x = 2;
        }
        // func(state);
            func(state);
        }

        if (state.icache_flushed) {
            assert(state.icbi_address % 32 == 0);
            
            for (u32 i = 0; i < 32; i += 4) {
                jit_hash_map.remove(state.icbi_address + i);    
            }
            
            state.icache_flushed = false;
        }

        // auto func = code.get_function!JitFunction();
                // auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
                // auto res = x86_capstone.disasm((cast(ubyte*) func)[0 .. code.getSize()], 0);
                // foreach (instr; res) {
                    // log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
                // }

        // if (mem.read_be_u32(state.pc) == 0x4d820020) {
            // int x = 2;
        // }
        // func(state);
        
        return 2;
    }

    private void log_instruction(u32 instruction, u32 pc) {
        // auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);
        // foreach (instr; res) {
            // log_broadway("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
        // }
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
}