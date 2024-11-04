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
        code.init();
        log_jit("GUEST lr: 0x%08x", state.lr);
        log_jit("GUEST ctr: 0x%08x", state.ctr);
        emit(code, mem, state.pc);
        
        import std.stdio;
        // dump register state, 8 regs at atime
        for (int i = 0; i < 32; i += 8) {
            writefln("GUEST r%d: 0x%08x r%d: 0x%08x r%d: 0x%08x r%d: 0x%08x r%d: 0x%08x r%d: 0x%08x r%d: 0x%08x r%d: 0x%08x",
                i, state.gprs[i], i + 1, state.gprs[i + 1], i + 2, state.gprs[i + 2], i + 3, state.gprs[i + 3],
                i + 4, state.gprs[i + 4], i + 5, state.gprs[i + 5], i + 6, state.gprs[i + 6], i + 7, state.gprs[i + 7]);
        }

        auto func = code.get_function!JitFunction();
                auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
                auto res = x86_capstone.disasm((cast(ubyte*) func)[0 .. code.getSize()], 0);
                foreach (instr; res) {
                    log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
                }

        if (mem.read_be_u32(state.pc) == 0x4d820020) {
            int x = 2;
        }
        func(state);
        
        return 1;
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