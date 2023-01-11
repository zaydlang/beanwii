module emu.hw.broadway.jit.jit;

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

    private Mem mem;
    private Code code;
    private IR* ir;

    private JitHashMap* jit_hash_map;

    this(JitConfig config, Mem mem) {
        this.mem          = mem;
        
        this.code         = new Code(config);
        this.ir           = new IR();
        this.jit_hash_map = new JitHashMap();
        
        this.ir.setup();
    }

    private u32 fetch(BroadwayState state) {
        u32 instruction = cast(u32) mem.read_be_u32(state.pc);
        log_broadway("Fetching %x from %x", instruction, state.pc);
        return instruction;
    }

    // returns the number of instructions executed
    public u32 run(BroadwayState state) {
        JitFunction cached_function = jit_hash_map.require(state.pc, null);

        if (cached_function != null) {
            cached_function(&state);
            return 1;
        } else {
            ir.reset();

            u32 instruction = fetch(state);
            // log_instruction(instruction, state.pc - 4);

            emit(ir, instruction, state.pc);

            code.reset();
            code.emit(ir);

            JitFunction generated_function = cast(JitFunction) code.getCode();
            
            jit_hash_map.opIndexAssign(generated_function, state.pc);

            state.pc += 4;
            generated_function(&state);

            return 1;
        }
    }
}