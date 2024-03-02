module emu.hw.broadway.jit.jit;

import capstone;
import dklib.khash;
// import emu.hw.broadway.jit.frontend.disassembler;
// import emu.hw.broadway.jit.backend.x86_64.emitter;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.passes.allocate_registers.pass;
import emu.hw.broadway.jit.passes.code_emission.pass;
import emu.hw.broadway.jit.passes.generate_recipe.pass;
import emu.hw.broadway.jit.passes.idle_loop_detection.pass;
import emu.hw.broadway.jit.passes.impose_x86_conventions.pass;
import emu.hw.broadway.jit.passes.optimize_get_reg.pass;
import emu.hw.broadway.jit.passes.optimize_set_reg.pass;
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

    private Mem          mem;
    private JitConfig    config;
    // private Code        code;
    private IR*          ir;
    private JitHashMap*  jit_hash_map;
    // private Capstone    capstone;
    private DebugRing    debug_ring;

    // private GenerateRecipe generate_recipe;
    private ImposeX86Conventions impose_x86_conventions;
    private AllocateRegisters allocate_registers;
    private CodeEmission code_emission;

    this(JitConfig config, Mem mem, size_t ringbuffer_size) {
        this.config = config;
        this.mem = mem;
        
        this.code_emission = new CodeEmission(config);
        this.impose_x86_conventions = new ImposeX86Conventions();
        this.allocate_registers = new AllocateRegisters();
        
        // // this.code         = new Code(config);
        // this.ir           = new IR();
        this.jit_hash_map = new JitHashMap();

        // this.capstone     = create(Arch.ppc, ModeFlags(Mode.bit32));
        // this.debug_ring   = new DebugRing(ringbuffer_size);
        
        // this.ir.setup();
    }

    private u32 fetch(BroadwayState* state) {
        u32 instruction = cast(u32) mem.read_be_u32(state.pc);
        return instruction;
    }

    // returns the number of instructions executed
    public u32 run(BroadwayState* state) {
        JitFunction cached_function = jit_hash_map.require(state.pc, null);

        if (cached_function != null) {
            cached_function(state);
        } else {
            IR* ir = new IR();
            ir.setup();
            ir.reset();

            allocate_registers.reset();
            code_emission.reset();

            JitContext ctx = JitContext(
                state.pc,
                state.hid2.bit(30) // HID2[PSE]
            );

            auto num_guest_instructions_processed = emu.hw.broadway.jit.passes.generate_recipe.pass.generate_recipe(ir, mem, ctx, state.pc);
            Recipe recipe = new Recipe(ir.get_instructions());

            log_jit("===== PPC Disassembly: =====");

            auto crapstone = capstone.create(Arch.ppc, ModeFlags(Mode.bit32));
            string disassembly = "";
            u32 current_address = state.pc;
            for (int i = 0; i < num_guest_instructions_processed; i++) {
                u32 instruction = mem.read_be_u32(current_address);
                auto res = crapstone.disasm((cast(ubyte*) &instruction)[0 .. 4], current_address);

                foreach (instr; res) {
                    import std.format;
                    log_jit(format("0x%08x | %s\t\t%s", current_address, instr.mnemonic, instr.opStr));
                }

                if (i != num_guest_instructions_processed - 1) {
                    disassembly ~= "\n";
                }

                current_address += 4;
            }

            IdleLoopDetection idle_loop_detection = new IdleLoopDetection();
            idle_loop_detection.init(ctx);
            recipe.pass(idle_loop_detection);
            // recipe.pass(new OptimizeGetReg());
            // recipe.pass(new OptimizeSetReg());
            recipe.pass(new ImposeX86Conventions());
            recipe.pass(new AllocateRegisters());

            log_state(state);

            log_jit("===== X86 Disassembly: =====");

            recipe.pass(code_emission);
            auto bazinga = code_emission.get_function();
            crapstone = capstone.create(Arch.x86, ModeFlags(Mode.bit64));
                    auto res = crapstone.disasm((cast(ubyte*) bazinga)[0 .. code_emission.get_function_size()], 0);
                    foreach (instr; res) {
                        log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
                    }
            jit_hash_map.opIndexAssign(bazinga, state.pc);
            bazinga(state);
            
        }



         
        // // TODO: jit this
        // // _mm_setcsr(0x1F80 | (0 << 13));

        // JitFunction cached_function = jit_hash_map.require(state.pc, null);

        // if (cached_function != null && false) {
        //     cached_function(state);
        //     return 1;
        // } else {
        //     ir.reset();

            // JitContext ctx = JitContext(
                // state.pc, 
                // state.hid2.bit(30) // HID2[PSE]
            // );

        //     u32 instruction = fetch(state);
        //     // log_instruction(instruction, ctx.pc);

        //     emit(ir, instruction, ctx);

        //     code.reset();
        //     code.emit(ir);

        //     JitFunction generated_function = cast(JitFunction) code.getCode();

        //     // if (instruction == 0x7cf68f96) {
        //     //     auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
        //     //     auto res = x86_capstone.disasm((cast(ubyte*) generated_function)[0 .. code.getSize()], 0);
        //     //     foreach (instr; res) {
        //     //         log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
        //     //     }

        //     //     b("jit");
        //     // }

        //     if (g_START_LOGGING) {
        //         int x = 2;
        //     }

        //     jit_hash_map.opIndexAssign(generated_function, state.pc);

        //     state.pc += 4;
        //     this.debug_ring.add(DebugState(*state, instruction));

        //     generated_function(state);

            return 100;
        // }
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