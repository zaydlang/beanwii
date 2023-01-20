module emu.hw.broadway.cpu;

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
    private HleContext    hle_context;

    private size_t        ringbuffer_size;

    public this(size_t ringbuffer_size) {
        this.ringbuffer_size = ringbuffer_size;
    }

    public void connect_mem(Mem mem) {
        this.mem = mem;
        this.hle_context = new HleContext(&this.mem);

        jit = new Jit(JitConfig(
            cast(ReadHandler)  (&this.mem.read_be_u8)   .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u16)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u32)  .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u8)  .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u16) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u32) .funcptr,
            cast(HleHandler)   (&this.hle_handler)      .funcptr,
            cast(void*) this.mem,
            cast(void*) this
        ), mem, ringbuffer_size);
    }

    public void reset() {
        for (int i = 0; i < 32; i++) {
            state.gprs[i] = 0;
        }

        state.cr   = 0;
        state.xer  = 0;
        state.ctr  = 0;
        state.msr  = 0;
        state.hid0 = 0;
        state.hid2 = 0;

        state.pc  = 0;
        state.lr  = 0;
    }

    // returns the number of instructions executed
    public u32 run() {
        // log_state(&state);
        return jit.run(&state);
    }

    public void run_until_return() {
        assert(this.state.pc != 0xDEADBEEF);

        this.state.lr = 0xDEADBEEF;

        while (this.state.pc != 0xDEADBEEF) {
            run();
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

    public void set_fpr(int fpr, double value) {
        *(cast(float*) &this.state.fprs[fpr]) = value;
    }

    public double get_fpr(int fpr) {
        return *(cast(double*) &this.state.fprs[fpr]);
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
}
