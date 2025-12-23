module emu.hw.broadway.cpu;

import core.bitop;
import emu.hw.broadway.exception_type;
import emu.hw.broadway.gdb;
import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.return_value;
import emu.hw.broadway.jit.jit;
import emu.hw.ipc.ipc;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import ldc.intrinsics;
import util.bitop;
import util.endian;
import util.force_cast; 
import util.log;
import util.number;
import std.stdio;

struct BroadwayReturnValue {
    u32 num_cycles_ran;
    bool should_enter_gdb;
}

int bazinga = 0;
__gshared 
    bool biglog = false;
final class Broadway {

    public  BroadwayState       state;
    public  Mem                 mem;
    public  Jit                 jit;
    private HleContext          hle_context;
    public  InterruptController interrupt_controller;
    private int                 ringbuffer_size;

    public  bool                should_log;

    public  Scheduler           scheduler;

    private ulong decrementer_event;

    private ulong last_timebase_update;
    private ulong last_decrementer_update;
    private u64 timebase;

    private GDBStub gdb_stub;

    private u32 entrypoint;

    public this(int ringbuffer_size) {
        this.ringbuffer_size = ringbuffer_size;
        this.interrupt_controller = new InterruptController();
        this.interrupt_controller.connect_cpu(this);
        this.should_log = false;
    }

    public void connect_gdb_stub(GDBStub gdb_stub) {
        this.gdb_stub = gdb_stub;
    }

    public void connect_mem(Mem mem) {
        this.mem = mem;
        this.hle_context = new HleContext(&this.mem);

        jit = new Jit(JitConfig(
            cast(ReadHandler8)   (&this.mem.cpu_read_physical_u8)   .funcptr,
            cast(ReadHandler16)  (&this.mem.cpu_read_physical_u16)  .funcptr,
            cast(ReadHandler32)  (&this.mem.cpu_read_physical_u32)  .funcptr,
            cast(ReadHandler64)  (&this.mem.cpu_read_physical_u64)  .funcptr,
            cast(WriteHandler8)  (&this.mem.cpu_write_physical_u8)  .funcptr,
            cast(WriteHandler16) (&this.mem.cpu_write_physical_u16) .funcptr,
            cast(WriteHandler32) (&this.mem.cpu_write_physical_u32) .funcptr,
            cast(WriteHandler64) (&this.mem.cpu_write_physical_u64) .funcptr,
            cast(ReadHandler8)   (&this.mem.cpu_read_virtual_u8)    .funcptr,
            cast(ReadHandler16)  (&this.mem.cpu_read_virtual_u16)   .funcptr,
            cast(ReadHandler32)  (&this.mem.cpu_read_virtual_u32)   .funcptr,
            cast(ReadHandler64)  (&this.mem.cpu_read_virtual_u64)   .funcptr,
            cast(WriteHandler8)  (&this.mem.cpu_write_virtual_u8)   .funcptr,
            cast(WriteHandler16) (&this.mem.cpu_write_virtual_u16)  .funcptr,
            cast(WriteHandler32) (&this.mem.cpu_write_virtual_u32)  .funcptr,
            cast(WriteHandler64) (&this.mem.cpu_write_virtual_u64)  .funcptr,
            cast(HleHandler)   (&this.hle_handler)      .funcptr,
            cast(MfsprHandler) (&this.mfspr_handler)    .funcptr,
            cast(MtsprHandler) (&this.mtspr_handler)    .funcptr,
            cast(void*) this.mem,
            cast(void*) this,
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
        state.dmau   = 0;
        state.dmal   = 0;

        state.pc     = 0;
        state.lr     = 0;

        state.halted = false;

        timebase = 0;
        last_timebase_update = scheduler.get_current_time();
        last_decrementer_update = scheduler.get_current_time();
    }

    int num_log = 0;
    bool idle = false;
    bool exception_raised = false;
    bool shitter = false;

    bool is_sussy(u64 foat) {
        auto mantissa = (foat >> 52) & 0b11111111111;
        return (mantissa == 0b11111111111);
    }

    bool debjit = false;
    bool had_17 = false;

    pragma(inline, true) public BroadwayReturnValue cycle(u32 num_cycles) {
        u32 elapsed = 0;
        size_t num_fast_forwarded = 0;
        while (elapsed < num_cycles) {
            exception_raised = false;

        // if (state.pc == 0x80245b40) {
        //     writefln("bad function %x %x %x from %x\n", state.gprs[3], state.gprs[4], state.gprs[5], state.lr);
        // }


        // for (int i = 0; i < 32; i++) {
        //     // if (state.gprs[i] == 0x90a2) {
        //     //     import std.stdio;
        //     //     writefln("sussy gpr %d at %x from %x\n", i, state.pc, state.lr);
        //     //     log_state(&state);
        //     // }

        //     double ps0 = force_cast!double(state.ps[i].ps0);
        //     double ps1 = force_cast!double(state.ps[i].ps1);
        //     double diff_ps0 = (ps0 - 5.49717);
        //     double diff_ps1 = (ps1 - 5.49717);
        //     double diff_ps0_abs = diff_ps0 < 0 ? -diff_ps0 : diff_ps0;
        //     double diff_ps1_abs = diff_ps1 < 0 ? -diff_ps1 : diff_ps1;
        //     if (diff_ps1_abs < 0.00001 || diff_ps0_abs < 0.00001) {
        //         import std.stdio;
        //         writefln("sussy ps %d at %x from %x\n", i, state.pc, state.lr);
        //         log_state(&state);
        //     }
        // }

        // if (state.pc >= 0x80007268 && state.pc <= 0x80007268) {
            // writefln("sussy fp %x from %x\n", state.pc, state.lr);
                // log_state(&state);
        // }

        bool was =(state.pc >= 0x805b86f0 && state.pc <= 0x805b8cd4);
            JitReturnValue jit_return_value = jit.run(&state);
            auto delta = jit_return_value.num_instructions_executed * 2;

            if (in_single_step_mode || jit_return_value.block_return_value.breakpoint_hit) {
                gdb_stub.breakpoint_hit(state.pc);
                return BroadwayReturnValue(elapsed, true);
            }

            if (jit_return_value.block_return_value.value == BlockReturnValue.FloatingPointUnavailable) {
                raise_exception(ExceptionType.FloatingPointUnavailable);
            } else if (jit_return_value.block_return_value.value == BlockReturnValue.IdleLoopDetected &&
                !jit_return_value.block_return_value.breakpoint_hit) {
                auto fast_forward = scheduler.tick_to_next_event();
                scheduler.process_events();
                elapsed += fast_forward;
                num_fast_forwarded += fast_forward;

                handle_pending_interrupts();

                if (elapsed < num_cycles) {
                    continue;
                } else {
                    return BroadwayReturnValue(elapsed, false);
                }
            }

            scheduler.tick(delta);
            scheduler.process_events();
        
            handle_pending_interrupts();
            elapsed += delta;
        }

        return BroadwayReturnValue(elapsed, false);
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
        // dump_stack();
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
    void handle_exception(ExceptionType type) {
        log_interrupt("Exception: %s. Pending: %x", type, pending_interrupts);
        if (exception_raised) error_jit("Exception already raised");
        exception_raised = true;

        assert(type == ExceptionType.Decrementer || type == ExceptionType.ExternalInterrupt || type == ExceptionType.FloatingPointUnavailable);

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
        case ExceptionType.ExternalInterrupt:        state.pc = base + 0x500; break;
        case ExceptionType.FloatingPointUnavailable: state.pc = base + 0x800; break;
        case ExceptionType.Decrementer:              state.pc = base + 0x900; break;
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
        log_interrupt("Pending interrupts: %x (%x)", pending_interrupts, state.msr.bit(15));
        if (pending_interrupts > 0) {
            auto exception_to_raise = core.bitop.bsf(pending_interrupts);
            
            // FloatingPointUnavailable bypasses MSR.EE check
            if (exception_to_raise == ExceptionType.FloatingPointUnavailable || state.msr.bit(15)) {
                log_interrupt("Handling pending interrupt: %x", pending_interrupts);
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
        import std.stdio;

        writefln("Dumping stack. pc: %x lr: %x", state.pc, state.lr);
        for (int i = 0; i < 500 / 8; i ++) {
            writefln("%08x %08x %08x %08x %08x %08x %08x %08x", 
                mem.cpu_read_u32(state.gprs[1] + i * 32),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 4),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 8),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 12),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 16),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 20),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 24),
                mem.cpu_read_u32(state.gprs[1] + i * 32 + 28));
        }
    }

    u32 mfspr_handler(GuestReg spr) {
        u32 value = 0;
        switch (spr) {
            case GuestReg.TBU: update_timebase(); value = timebase >> 32; break;
            case GuestReg.TBL: update_timebase(); value = timebase & 0xFFFF_FFFF; break;
            case GuestReg.DEC: update_decrementer(); value = state.dec; break;
            case GuestReg.DMAU: value = get_dma_upper(); break;
            case GuestReg.DMAL: value = get_dma_lower(); break;
            default: error_broadway("Unexpected MFSPR: %s (%x)", spr, spr);
        }

        return value;
    }

    void mtspr_handler(GuestReg spr, u32 value) {
        switch (spr) {
            case GuestReg.TBU: 
                timebase = (timebase & 0xFFFF_FFFF) | (cast(u64) value << 32);
                last_timebase_update = scheduler.get_current_time();
                break;

            case GuestReg.TBL:
                timebase = (timebase & 0xFFFF_FFFF_0000_0000) | value;
                last_timebase_update = scheduler.get_current_time();
                break;
            
            case GuestReg.DEC: 
                set_decrementer(value);
                break;

            case GuestReg.DMAU:
                set_dma_upper(value);
                break;

            case GuestReg.DMAL:
                set_dma_lower(value);
                break;

            default: error_broadway("Unexpected MTSPR: %s (%x)", spr, spr);
        }
    }

    struct DmaEvent {
        u32 lc_address;
        bool dma_ld;
        u32 dma_len;
        u32 mem_addr;

        ulong scheduler_id;
    }

    DmaEvent[] enqueued_dma_events;

    // DMA Address Register handlers (skeleton implementation)
    u32 get_dma_upper() {
        log_broadway("Getting DMA Upper Address: %x", state.dmau);
        return state.dmau;
    }

    u32 get_dma_lower() {
        log_broadway("Getting DMA Lower Address: %x", state.dmal);
        return state.dmal;
    }

    void set_dma_upper(u32 value) {
        log_broadway("Setting DMA Upper Address: %x", value);
        state.dmau = value;
    }

    void set_dma_lower(u32 value) {
        log_broadway("Setting DMA Lower Address: %x", value);
        state.dmal = value;

        bool flush   = state.dmal.bit(0);
        bool trigger = state.dmal.bit(1);

        if (flush) {
            foreach (enqueued_dma_event; enqueued_dma_events) {
                scheduler.remove_event(enqueued_dma_event.scheduler_id);
            }
            enqueued_dma_events = [];

            assert_broadway(!trigger, "DMA flush and trigger are both set. Not sure what to do here.");
        }

        if (trigger) {
            u32  lc_address = (state.dmal & ~31);
            bool dma_ld = state.dmau.bit(4);
            u32  dma_len = ((state.dmau.bits(0, 4) << 2) | state.dmal.bits(2, 3)) * 32;
            u32  mem_addr = (state.dmau & ~31);

            DmaEvent dma_event = DmaEvent(
                lc_address:   lc_address,
                dma_ld:       dma_ld,
                dma_len:      dma_len,
                mem_addr:     mem_addr,
                scheduler_id: 0
            );

            dma_event.scheduler_id = scheduler.add_event_relative_to_clock(() => process_dma(dma_event), 1000);
            enqueued_dma_events ~= dma_event;
        }
    }

    void process_dma(DmaEvent dma_event) {
        log_broadway("Processing DMA: %x %x %x %x", dma_event.lc_address, dma_event.dma_ld, dma_event.dma_len, dma_event.mem_addr);

        if (dma_event.dma_ld) {
            for (int i = 0; i < dma_event.dma_len; i += 4) {
                u32 value = mem.physical_read_u32(dma_event.mem_addr + i);
                mem.physical_write_u32(dma_event.lc_address + i, value);
            }
        } else {
            for (int i = 0; i < dma_event.dma_len; i += 4) {
                u32 value = mem.physical_read_u32(dma_event.lc_address + i);
                mem.physical_write_u32(dma_event.mem_addr + i, value);
            }
        }
    }

    void update_decrementer() {
        auto current_time = scheduler.get_current_time();
        auto delta = current_time - last_decrementer_update;
        last_decrementer_update = current_time;

        state.dec -= delta / 12;        
    }

    void set_decrementer(u32 value) {
        log_function("Setting decrementer: %x %x %x", value, state.pc, state.lr);

        state.dec = value;

        scheduler.remove_event(decrementer_event);
        decrementer_event = scheduler.add_event_relative_to_clock(() => raise_exception(ExceptionType.Decrementer), cast(u64) value * 12);
    }

    void update_timebase() {
        auto current_time = scheduler.get_current_time();
        auto delta = current_time - last_timebase_update;
        last_timebase_update = current_time;

        // log_broadway("Updating timebase: %x %x", delta, timebase);
        timebase += delta / 12;
    }

    void add_breakpoint(u32 address) {
        jit.add_breakpoint(address);
    }

    void connect_gdb(GDBStub gdb_stub) {
        this.gdb_stub = gdb_stub;
    }

    bool in_single_step_mode;

    void enter_single_step_mode() {
        in_single_step_mode = true;
        jit.enter_single_step_mode();
    }

    void exit_single_step_mode() {
        in_single_step_mode = false;
        jit.exit_single_step_mode();
    }

    void dump_jit_entries() {
        jit.dump_all_entries();
    }
}
 