module emu.hw.broadway.cpu;

import emu.hw.broadway.exception_type;
import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.jit;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.endian;
import util.log;
import util.number;

final class Broadway {
    bool biglog = false;

    public  BroadwayState       state;
    private Mem                 mem;
    private Jit                 jit;
    private HleContext          hle_context;
    private InterruptController interrupt_controller;
    private size_t              ringbuffer_size;

    public  bool                should_log;

    private Scheduler           scheduler;

    public this(size_t ringbuffer_size) {
        this.ringbuffer_size = ringbuffer_size;
        this.interrupt_controller = new InterruptController();
        this.interrupt_controller.connect_cpu(this);
        this.should_log = false;
    }

    public void connect_mem(Mem mem) {
        this.mem = mem;
        this.hle_context = new HleContext(&this.mem);

        jit = new Jit(JitConfig(
            cast(ReadHandler)  (&this.mem.read_be_u8)   .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u16)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u32)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u64)  .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u8)  .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u16) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u32) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u64) .funcptr,
            cast(HleHandler)   (&this.hle_handler)      .funcptr,
            cast(void*) this.mem,
            cast(void*) this
        ), mem, ringbuffer_size);
    }

    public void reset() {
        for (int i = 0; i < 32; i++) {
            state.gprs[i] = 0;
        }

        state.cr     = 0;
        state.xer    = 0;
        state.ctr    = 0;
        state.msr    = 0x00002032;
        state.hid0   = 0;
        state.hid2   = 0xE0000000;
        state.hid4   = 0;
        state.srr0   = 0;
        state.srr1   = 0;
        state.fpsr   = 0;
        state.fpscr  = 0;
        state.l2cr   = 0;
        state.mmcr0  = 0;
        state.mmcr1  = 0;
        state.pmc1   = 0;
        state.pmc2   = 0;
        state.pmc3   = 0;
        state.pmc4   = 0;
        state.tbu    = 0;
        state.tbl    = 0;
        state.sprg0  = 0;

        state.pc     = 0;
        state.lr     = 0;

        state.halted = false;
    }

    int num_log = 0;
    bool idle = false;
    bool exception_raised = false;

    public void cycle(u32 num_cycles) {
        if (state.halted) {
            log_jit("CPU is halted, not running\n");
        }

        
        u32 elapsed = 0;
        while (elapsed < num_cycles && !state.halted) {
            exception_raised = false;
        // if (biglog) {
        //     // num_log--;
        //     log_jit("PC: %08X\n", state.pc);
        //     log_state(state);
        // }

            if (state.pc == 0x80004420) {
                log_jit("[FUNCTION] _cpu_context_switch");
            }
            if (state.pc == 0x800169b0) {
                if (!idle) {
log_jit("[FUNCTION] idle_func");
                }
                idle = true;
            } else {
                idle = false;
            }

            if (state.pc == 0x800068fc) {
                log_jit("[FUNCTION] __crt_main()");
                // should_log = true;
            }
            if (state.pc == 0x8001bd1c) {
                log_jit("[FUNCTION] SYS_Init()");
            }
            if (state.pc == 0x80022808) {
                log_jit("[FUNCTION] ipc sync()");
            }
            if (state.pc == 0x80022704) {
                log_jit("[FUNCTION] ipc send()");
            }
            
            if (state.pc == 0x80016e94) {
                log_jit("[FUNCTION] LWP_ThreadSleep(%x)", state.gprs[3]);
            }

            if (state.pc == 0x80017014) {
                log_jit("[FUNCTION] LWP_ThreadSignal(%x)", state.gprs[3]);
            }
        
            if (biglog) {
                u32 opcode = mem.read_be_u32(state.pc);
                // log_jit("PC: %08X, Opcode: %08X\n", state.pc, opcode);
                log_state(&state);
            }


            auto nobr = state.pc + 4;
            auto older_dec = state.dec;
            auto delta = jit.run(&state);
            if (older_dec != state.dec) {
                log_jit("Decrementer changed from %0x to %0x\n", older_dec, state.dec);
            }

            if (state.pc != nobr && state.pc != nobr - 4) {
                log_jit("Branching from %08X to %08X\n", nobr - 4, state.pc);
            }
            scheduler.tick(delta);
            scheduler.process_events();

            // todo: yeet this to the scheduler
            u64 time_base = cast(u64) state.tbu << 32 | cast(u64) state.tbl;
            time_base += delta;
            state.tbu = cast(u32) (time_base >> 32);
            state.tbl = cast(u32) time_base;

            log_jit("tbu: %08X, tbl: %08X\n", state.tbu, state.tbl);

            // check for decrementer interrupt
            auto old_dec = state.dec;
            state.dec -= delta;
            if (old_dec > 0 && state.dec <= 0 && state.msr.bit(15)) {
                log_jit("Raising decrementer interrupt\n");
                // num_log = 100;
                raise_exception(ExceptionType.Decrementer);
            } else {
                interrupt_controller.maybe_raise_processor_interface_interrupt();
            }


            elapsed += delta;
        }
    }

    // TODO: do single stepping properly
    public void single_step() {
        cycle(1);
    }

    public void run_until_return() {
        assert(this.state.pc != 0xDEADBEEF);

        this.state.lr = 0xDEADBEEF;

        while (this.state.pc != 0xDEADBEEF) {
            cycle(1);
        }
    }

    public HleContext* get_hle_context() {
        return &this.hle_context;
    }

    private void hle_handler(int function_id) {
        this.hle_context.hle_handler(&this.state, function_id);
        this.state.pc = this.state.lr;
    }

    public void on_error() {
        jit.on_error();
    }

    // here are the really annoying-to-write functions:

    public void set_gpr(int gpr, u32 value) {
        this.state.gprs[gpr] = value;
    }

    public u32 get_gpr(int gpr) {
        return this.state.gprs[gpr];
    }

    public void set_gqr(int gqr, u32 value) {
        this.state.gqrs[gqr] = value;
    }

    public u32 get_gqr(int gqr) {
        return this.state.gqrs[gqr];
    }

    public void set_cr(int cr, u32 value) {
        this.state.cr = (this.state.cr & ~(0xF << (cr * 4))) | (value << (cr * 4));
    }

    public u32 get_cr(int cr) {
        return (this.state.cr >> (cr * 4)) & 0xF;
    }

    public void set_xer(u32 value) {
        this.state.xer = value;
    }

    public u32 get_xer() {
        return this.state.xer;
    }

    public void set_ctr(u32 value) {
        this.state.ctr = value;
    }

    public u32 get_ctr() {
        return this.state.ctr;
    }

    public void set_msr(u32 value) {
        this.state.msr = value;
    }

    public u32 get_msr() {
        return this.state.msr;
    }

    public void set_hid0(u32 value) {
        this.state.hid0 = value;
    }

    public u32 get_hid0() {
        return this.state.hid0;
    }

    public void set_hid2(u32 value) {
        this.state.hid2 = value;
    }

    public u32 get_hid2() {
        return this.state.hid2;
    }

    public void set_lr(u32 lr) {
        state.lr = lr;
    }

    public u32 get_lr() {
        return state.lr;
    }

    public void set_pc(u32 pc) {
        state.pc = pc;
    }

    public u32 get_pc() {
        return state.pc;
    }

    public InterruptController get_interrupt_controller() {
        return this.interrupt_controller;
    }

    // SRR1[0,5-9,16-23,25-27,30-31]
    void raise_exception(ExceptionType type) {
        if (exception_raised) error_jit("Exception already raised");
        exception_raised = true;

        assert(type == ExceptionType.Decrementer || type == ExceptionType.ExternalInterrupt);

        state.srr0 = state.pc;
        state.srr1 &= ~(0b0000_0111_1100_0000_1111_1111_1111_1111);
        state.srr1 |= state.msr & (0b0000_0111_1100_0000_1111_1111_1111_1111);

        // clear IR and DR
        state.msr &= ~(1 << 4 | 1 << 5);

        // clear RI
        state.msr &= ~(1 << 30);

        // this exception *is* recoverable
        state.srr1 |= (1 << 30);

        // clear POW, EE, PR, FP, FE0, SE, BE, FE1, PM
        state.msr &= ~(0b0000_0000_0000_0100_1110_1111_0000_0000);

        // copy ILE to LE
        state.msr |= state.msr.bit(16);

        bool ip = state.msr.bit(6);
        u32 base = ip ? 0xFFF0_0000 : 0x0000_0000;

        switch (type) {
        case ExceptionType.ExternalInterrupt: state.pc = base + 0x500; break;
        case ExceptionType.Decrementer:       state.pc = base + 0x900; break;
        default: assert(0);
        }

        log_jit("Raised exception %s\n", type);
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }
}
