module emu.hw.broadway.cpu;

import core.bitop;
import emu.hw.broadway.exception_type;
import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.emission.return_value;
import emu.hw.broadway.jit.jit;
import emu.hw.ipc.ipc;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.endian;
import util.log;
import util.number;
import std.stdio;

int bazinga = 0;
__gshared 
    bool biglog = false;
final class Broadway {

    public  BroadwayState       state;
    private Mem                 mem;
    private Jit                 jit;
    private HleContext          hle_context;
    public InterruptController interrupt_controller;
    private size_t              ringbuffer_size;

    public  bool                should_log;

    private Scheduler           scheduler;

    private ulong decrementer_event;

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
    bool shitter = false;
    int cunt = 0;

    bool is_sussy(u64 foat) {
        return (foat & 0x0000_ffff_ffff_0000) == 0x0000_0000_7fff_0000 || foat == 0x4330000000000000;
    }

    void sussy_floats() {
        for (int i = 0; i < 32; i++) {
            if (is_sussy(state.ps[i].ps0) || is_sussy(state.ps[i].ps1)) {
                log_function("BIG CHANGE: %x %x\n", mem.read_be_u32(state.pc - 4), 0);
                // log_state(&state);
                error_function("sussy float!\n");
            }
        }
    }

    public void cycle(u32 num_cycles) {
        if (state.halted) {
            log_function("CPU is halted, not running\n");
        }

        
        u32 elapsed = 0;
        while (elapsed < num_cycles) {
            exception_raised = false;
            u32 old_pc = state.pc;
            if (state.pc >= 0x802778d4 && state.pc <= 0x80277930) {
                // log_broadway("PSMTXIdentity(%08x)", state.gprs[3]);
                // log_state(&state);
            }
            // log_jit("At pc: %x", old_pc);
            // log_state(&state);
            JitReturnValue jit_return_value = jit.run(&state);
            auto delta = jit_return_value.num_instructions_executed * 2;
            if (jit_return_value.block_return_value == BlockReturnValue.DecrementerChanged) {
                scheduler.remove_event(decrementer_event);
                decrementer_event = scheduler.add_event_relative_to_clock(() => raise_exception(ExceptionType.Decrementer), state.dec);
            } else if (jit_return_value.block_return_value == BlockReturnValue.CpuHalted) {
                auto fast_forward = scheduler.tick_to_next_event();
                scheduler.process_events();
                elapsed += fast_forward;

                if (elapsed < num_cycles) {
                    return;
                } else {
                    continue;
                }
            }

            state.dec -= delta;

            scheduler.tick(delta);
            scheduler.process_events();

            // todo: yeet this to the scheduler
            u64 time_base = cast(u64) state.tbu << 32 | cast(u64) state.tbl;
            time_base += delta;
            state.tbu = cast(u32) (time_base >> 32);
            state.tbl = cast(u32) time_base;

            if (state.pc == 0) {
                error_jit("PC is zero, %x", old_pc);
            }
        
            handle_pending_interrupts();
            elapsed += delta;
        }

        // log_function("decrementer: %x %x", state.dec, state.dar);
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
        log_function("ERROR DETECTED");
        log_state(&state);
        jit.on_error();

        import util.dump;
        dump(this.mem.mem1, "mem1.bin");
        dump(this.mem.mem2, "mem2.bin");
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
    void handle_exception(ExceptionType type) {
        log_interrupt("Exception: %s. Pending: %x", type, pending_interrupts);
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
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_ipc(IPC ipc) {
        this.interrupt_controller.connect_ipc(ipc);
    }

    int pending_interrupts = 0;
    void handle_pending_interrupts() {
        if (pending_interrupts > 0) {
            if (state.msr.bit(15)) {
                // log_function("Handling pending interrupt: %x", pending_interrupts);
                auto exception_to_raise = core.bitop.bsf(pending_interrupts);
                // log_function("Raising exception: %s", exception_to_raise);
                handle_exception(cast(ExceptionType) exception_to_raise);
                pending_interrupts &= ~(1 << exception_to_raise);
            } else {
                // interrupt_controller.maybe_raise_processor_interface_interrupt();
            }
        }
    }

    void raise_exception(ExceptionType type) {
        log_interrupt("Raise exception: %s %d", type, state.msr.bit(15));
        pending_interrupts |= (1 << type);
    }

    void set_exception(ExceptionType type, bool value) {
        if (value) {
            pending_interrupts |= (1 << type);
        } else {
            pending_interrupts &= ~(1 << type);
        }
    }

    void dump_stack() {
        log_broadway("Dumping stack. pc: %x lr: %x", state.pc, state.lr);
        for (int i = 0; i < 500; i++) {
            log_broadway("stack[%x] = 0x%08x", i, mem.read_be_u32(state.gprs[1] + i * 4));
        }
    }
}
 