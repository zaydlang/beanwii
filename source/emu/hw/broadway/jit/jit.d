module emu.hw.broadway.jit.jit;

import capstone;
import dklib.khash;
import emu.hw.broadway.jit.frontend.disassembler;
import emu.hw.broadway.jit.backend.x86_64.emitter;
import emu.hw.broadway.jit.ir.ir;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
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

    private Mem         mem;
    private Code        code;
    private IR*         ir;
    private JitHashMap* jit_hash_map;

    private Capstone    capstone;
    private DebugRing   debug_ring;

    this(JitConfig config, Mem mem, size_t ringbuffer_size) {
        this.mem          = mem;
        
        this.code         = new Code(config);
        this.ir           = new IR();
        this.jit_hash_map = new JitHashMap();

        this.capstone     = create(Arch.ppc, ModeFlags(Mode.bit32));
        this.debug_ring   = new DebugRing(ringbuffer_size);
        
        this.ir.setup();
    }

    private u32 fetch(BroadwayState* state) {
        u32 instruction = cast(u32) mem.read_be_u32(state.pc);
        return instruction;
    }

    // returns the number of instructions executed
    public u32 run(BroadwayState* state) {
        // TODO: jit this
        // _mm_setcsr(0x1F80 | (0 << 13));

        JitFunction cached_function = jit_hash_map.require(state.pc, null);

        if (cached_function != null && false) {
            cached_function(state);
            return 1;
        } else {
            ir.reset();

            JitContext ctx = JitContext(
                state.pc, 
                state.hid2.bit(30) // HID2[PSE]
            );

            u32 instruction = fetch(state);
            // log_instruction(instruction, ctx.pc);

            emit(ir, instruction, ctx);

            code.reset();
            code.emit(ir);

            JitFunction generated_function = cast(JitFunction) code.getCode();

            // if (instruction == 0x7cf68f96) {
            //     auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
            //     auto res = x86_capstone.disasm((cast(ubyte*) generated_function)[0 .. code.getSize()], 0);
            //     foreach (instr; res) {
            //         log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
            //     }

            //     b("jit");
            // }

            if (g_START_LOGGING) {
                int x = 2;
            }

            jit_hash_map.opIndexAssign(generated_function, state.pc);

            state.pc += 4;
            this.debug_ring.add(DebugState(*state, instruction));

            generated_function(state);

            return 1;
        }
    }

    private void log_instruction(u32 instruction, u32 pc) {
        auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);
        foreach (instr; res) {
            log_broadway("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
        }
    }

    public void on_error() {
        this.dump_debug_ring();
    }

    private void dump_debug_ring() {
        foreach (debug_state; this.debug_ring.get()) {
            log_instruction(debug_state.instruction, debug_state.state.pc - 4);
            log_state(&debug_state.state);
        }
    }
}