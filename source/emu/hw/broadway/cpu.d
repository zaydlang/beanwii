module emu.hw.broadway.cpu;

import capstone;
import emu.hw.broadway.hle;
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

    private IR*           ir;
    private JitConfig     config;
    private Code          code;
    private Capstone      capstone;

    private HleContext    hle_context;

    this(Mem mem) {
        this.mem = mem;
        this.capstone = create(Arch.ppc, ModeFlags(Mode.bit32));
        this.ir = new IR();

        this.config = JitConfig(
            cast(ReadHandler)  (&this.mem.read_be_u32)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u16)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u8)   .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u32) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u16) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u8)  .funcptr,
            cast(HleHandler)   (&this.hle_handler)      .funcptr,
            cast(void*) this.mem,
            cast(void*) this.hle_context
        );

        this.code = new Code(config);

        this.hle_context = new HleContext(&this.mem);

        this.ir.setup();
        this.reset();
    }

    public void reset() {
        for (int i = 0; i < 32; i++) {
            state.gprs[i] = 0;
        }

        state.cr  = 0;
        state.xer = 0;
        state.ctr = 0;

        state.pc  = 0;
        state.lr  = 0;
    }

    public void set_pc(u32 pc) {
        state.pc = pc;
    }

    public void run_instruction() {
        this.ir.reset();

        u32 instruction = fetch();
        log_instruction(instruction, state.pc - 4);

        emit(ir, instruction, state.pc);

        code.reset();
        code.emit(ir);

        auto generated_function = cast(void function(BroadwayState* state)) code.getCode();

        log_jit("before %x", &this.state);
        
        if (instruction == 0x80010024) {
            auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
            auto res = x86_capstone.disasm((cast(ubyte*) generated_function)[0 .. 256], 0);
            foreach (instr; res) {
                log_broadway("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
            }
        }

        generated_function(&this.state);

        log_state();
    }

    public void run_until_return() {
        this.state.lr = 0xDEADBEEF;

        while (this.state.pc != 0xDEADBEEF) {
            run_instruction();
        }
    }

    private void log_state() {
        for (int i = 0; i < 32; i += 8) {
            log_broadway("0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x",
                this.state.gprs[i + 0], this.state.gprs[i + 1], this.state.gprs[i + 2], this.state.gprs[i + 3],
                this.state.gprs[i + 4], this.state.gprs[i + 5], this.state.gprs[i + 6], this.state.gprs[i + 7]
            );
        }

        log_broadway("cr:  0x%08x", state.cr);
        log_broadway("xer: 0x%08x", state.xer);
        log_broadway("ctr: 0x%08x", state.xer);

        log_broadway("lr:  0x%08x", state.lr);
        log_broadway("pc:  0x%08x", state.pc);
    }

    private void log_instruction(u32 instruction, u32 pc) {
        auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);
        foreach (instr; res) {
            log_broadway("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
        }
    }

    private u32 fetch() {
        u32 instruction = cast(u32) mem.read_be_u32(state.pc);
        log_broadway("Fetching %x from %x", instruction, state.pc);
        state.pc += 4;
        return instruction;
    }

    public void set_gpr(int gpr, u32 value) {
        this.state.gprs[gpr] = value;
    }

    public u32 get_gpr(int gpr) {
        return this.state.gprs[gpr];
    }

    public HleContext* get_hle_context() {
        return &this.hle_context;
    }

    private void hle_handler(int function_id) {
        this.hle_context.hle_handler(&this.state, function_id);
        this.state.pc = this.state.lr;
    }
}
