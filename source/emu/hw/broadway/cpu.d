module emu.hw.broadway.cpu;

import capstone;
import emu.hw.broadway.hle;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.jit;
import emu.hw.memory.strategy.memstrategy;
import util.endian;
import util.log;
import util.number;

final class Broadway {
    private Mem           mem;
    private BroadwayState state;
    private Jit           jit;

    private Capstone      capstone;

    private HleContext    hle_context;

    this() {
        this.capstone = create(Arch.ppc, ModeFlags(Mode.bit32));
    }

    public void connect_mem(Mem mem) {
        this.mem = mem;

        jit = new Jit(JitConfig(
            cast(ReadHandler)  (&this.mem.read_be_u32)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u16)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u8)   .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u32) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u16) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u8)  .funcptr,
            cast(HleHandler)   (&this.hle_handler)      .funcptr,
            cast(void*) this.mem,
            cast(void*) this.hle_context
        ), mem);

        this.hle_context = new HleContext(&this.mem);
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

    // returns the number of instructions executed
    public u32 run() {
        return jit.run(state);
    }

    public void run_until_return() {
        this.state.lr = 0xDEADBEEF;

        while (this.state.pc != 0xDEADBEEF) {
            run();
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
        log_broadway("ctr: 0x%08x", state.ctr);

        log_broadway("lr:  0x%08x", state.lr);
        log_broadway("pc:  0x%08x", state.pc);
    }

    private void log_instruction(u32 instruction, u32 pc) {
        auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);
        foreach (instr; res) {
            log_broadway("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
        }
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
