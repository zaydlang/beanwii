module emu.hw.broadway.cpu;

import capstone;
import emu.hw.broadway.jit.frontend.disassembler;
import emu.hw.broadway.jit.backend.x86_64.emitter;
import emu.hw.broadway.jit.ir.ir;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import util.endian;
import util.log;
import util.number;

final class BroadwayCpu {
    private Mem           mem;
    private BroadwayState state;

    private Capstone      capstone;

    this(Mem mem) {
        this.mem      = mem;
        this.capstone = create(Arch.ppc, ModeFlags(Mode.bit32));

        this.reset();
    }

    void reset() {
        for (int i = 0; i < 32; i++) {
            state.gprs[i] = 0;
        }

        state.pc = 0;
        state.lr = 0;
    }

    public void set_pc(u32 pc) {
        state.pc = pc;
    }

    public void run_instruction() {
        u32 instruction = fetch();
        log_instruction(instruction);

        IR* ir = new IR();
        ir.setup();
        ir.reset();
        emit(ir, instruction, state.pc);

        JitConfig config = JitConfig(
            cast(ReadHandler) ( &mem.read_be_u32) .funcptr,
            cast(ReadHandler)  (&mem.read_be_u16) .funcptr,
            cast(ReadHandler)  (&mem.read_be_u8)  .funcptr,
            cast(WriteHandler) (&mem.write_be_u32).funcptr,
            cast(WriteHandler) (&mem.write_be_u16).funcptr,
            cast(WriteHandler) (&mem.write_be_u8) .funcptr,
            cast(void*) mem
        );

        Code code = new Code(config);
        code.reset();
        code.emit(ir);

        auto generated_function = cast(void function(BroadwayState* state)) code.getCode();

        // log_jit("before %x", &this.state);
        generated_function(&this.state);
        // log_jit("after %x", &this.state);

        log_state();
    }

    private void log_state() {
        for (int i = 0; i < 32; i += 8) {
            log_broadway("0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x",
                this.state.gprs[i + 0], this.state.gprs[i + 1], this.state.gprs[i + 2], this.state.gprs[i + 3],
                this.state.gprs[i + 4], this.state.gprs[i + 5], this.state.gprs[i + 6], this.state.gprs[i + 7]
            );
        }

        log_broadway("lr: 0x%08x", state.lr);
        log_broadway("pc: 0x%08x", state.pc);
    }

    private void log_instruction(u32 instruction) {
        auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], 4);
        foreach (instr; res) {
            log_broadway("0x%08x | %s\t\t%s", instruction, instr.mnemonic, instr.opStr);
        }
    }

    private u32 fetch() {
        u32 instruction = cast(u32) mem.read_be_u32(state.pc);
        state.pc += 4;
        return instruction;
    }

    public void set_gpr(int gpr, u32 value) {
        this.state.gprs[gpr] = value;
    }
}
