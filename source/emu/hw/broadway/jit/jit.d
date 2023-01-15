module emu.hw.broadway.jit.jit;

import capstone;
import dklib.khash;
import emu.hw.broadway.jit.frontend.disassembler;
import emu.hw.broadway.jit.backend.x86_64.emitter;
import emu.hw.broadway.jit.ir.ir;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import util.log;
import util.number;

alias ReadHandler  = u32 function(u32 address);
alias WriteHandler = void function(u32 address, u32 value);
alias HleHandler   = void function(int param);

struct JitConfig {
    ReadHandler  read_handler32;
    ReadHandler  read_handler16;
    ReadHandler  read_handler8;
    WriteHandler write_handler32;
    WriteHandler write_handler16;
    WriteHandler write_handler8;
    HleHandler   hle_handler;

    void*        mem_handler_context;
    void*        hle_handler_context;
}

final class Jit {
    private alias JitFunction = void function(BroadwayState* state);
    private alias JitHashMap = khash!(u32, JitFunction);

    private Mem         mem;
    private Code        code;
    private IR*         ir;
    private JitHashMap* jit_hash_map;

    private Capstone    capstone;

    this(JitConfig config, Mem mem) {
        this.mem          = mem;
        
        this.code         = new Code(config);
        this.ir           = new IR();
        this.jit_hash_map = new JitHashMap();

        this.capstone     = create(Arch.ppc, ModeFlags(Mode.bit32));
        
        this.ir.setup();
    }

    private u32 fetch(BroadwayState* state) {
        u32 instruction = cast(u32) mem.read_be_u32(state.pc);
        return instruction;
    }

    // returns the number of instructions executed
    public u32 run(BroadwayState* state) {
        JitFunction cached_function = jit_hash_map.require(state.pc, null);

        if (cached_function != null && false) {
            cached_function(state);
            return 1;
        } else {
            ir.reset();

            u32 instruction = fetch(state);
            // log_instruction(instruction, state.pc);

            emit(ir, instruction, state.pc);

            code.reset();
            code.emit(ir);

            JitFunction generated_function = cast(JitFunction) code.getCode();

            // if (instruction == 0x7c831e30) {
                // auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
                // auto res = x86_capstone.disasm((cast(ubyte*) generated_function)[0 .. 256], 0);
                // foreach (instr; res) {
                //     log_broadway("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
                // }

                // error_jit("jit");
            // }

            jit_hash_map.opIndexAssign(generated_function, state.pc);

            state.pc += 4;
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
}