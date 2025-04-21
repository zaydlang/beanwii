module emu.hw.broadway.interrupt;

import emu.hw.broadway.cpu;
import emu.hw.broadway.exception_type;
import emu.hw.ipc.ipc;
import util.bitop;
import util.log;
import util.number;

enum HollywoodInterruptCause {
    IPC = 30,
}

enum ProcessorInterfaceInterruptCause {
    AI        = 5,
    DSP       = 6,
    VI        = 8,
    PeToken   = 9,
    PeFinish  = 10,
    Hollywood = 14,
}

final class InterruptController {
    this() {
        hollywood_interrupt_mask = 1 << HollywoodInterruptCause.IPC;
    }

    Broadway broadway;
    IPC ipc;
    
    void connect_cpu(Broadway broadway) {
        this.broadway = broadway;
    }

    u32 pi_interrupt_mask;

    u8 read_INTERRUPT_MASK(int target_byte) {
        return pi_interrupt_mask.get_byte(target_byte);
    }

    void write_INTERRUPT_MASK(int target_byte, u8 value) {
        set_interrupt_mask(pi_interrupt_mask.set_byte(target_byte, value));
    }

    u32 hollywood_interrupt_flag;

    u8 read_HW_PPCIRQFLAG(int target_byte) {
        log_interrupt("read HW_PPCIRQFLAG[%d] = %02x", target_byte, hollywood_interrupt_flag.get_byte(target_byte));
        return hollywood_interrupt_flag.get_byte(target_byte);
    }

    void write_HW_PPCIRQFLAG(int target_byte, u8 value) {
        // log_hollywood("HW_PPCIRQFLAG[%d] = %02x", target_byte, value);

        bool was_ipc_raised = (hollywood_interrupt_flag & (1 << HollywoodInterruptCause.IPC)) != 0;
        set_hollywood_interrupt_flag(hollywood_interrupt_flag.set_byte(
            target_byte, hollywood_interrupt_flag.get_byte(target_byte) & ~value));
        
        bool is_ipc_raised = (hollywood_interrupt_flag & (1 << HollywoodInterruptCause.IPC)) != 0;
        if (was_ipc_raised && !is_ipc_raised) {
            // log_hollywood("InterruptController: IPC interrupt acknowledged %x", broadway.state.pc);
            ipc.interrupt_acknowledged();
        }
    }

    bool ipc_interrupt_pending() {
        log_interrupt("Hollywood interrupt pending: %s", (hollywood_interrupt_flag & (1 << HollywoodInterruptCause.IPC)) != 0);
        return (hollywood_interrupt_flag & (1 << HollywoodInterruptCause.IPC)) != 0;
    }

    u32 hollywood_interrupt_mask;

    u8 read_HW_PPCIRQMASK(int target_byte) {
        return hollywood_interrupt_mask.get_byte(target_byte);
    }

    void write_HW_PPCIRQMASK(int target_byte, u8 value) {
        set_hollywood_interrupt_mask(hollywood_interrupt_mask.set_byte(target_byte, value));
    }

    u8 read_UNKNOWN_CC003024(int target_byte) {
        return 0;
    }

    void write_UNKNOWN_CC003024(int target_byte, u8 value) {
        error_interrupt("apparently this causes a complete fucking reset????? lol");
    }

    u8 read_UNKNOWN_CC00302C(int target_byte) {
        return 0x20000000.get_byte(target_byte);
    }

    void write_UNKNOWN_CC00302C(int target_byte, u8 value) {
        error_interrupt("Write to unknown interrupt controller register 0xCC00302C: %02x", value);
    }

    u32 pi_interrupt_cause;

    u8 read_INTERRUPT_CAUSE(int target_byte) {
        log_interrupt("InterruptController: read INTERRUPT_CAUSE[%d] = %02x", target_byte, pi_interrupt_cause.get_byte(target_byte));
        return pi_interrupt_cause.get_byte(target_byte);
    }

    void write_INTERRUPT_CAUSE(int target_byte, u8 value) {
        log_interrupt("InterruptController: write INTERRUPT_CAUSE[%d] = %02x", target_byte, value);
        set_interrupt_cause(pi_interrupt_cause.set_byte(target_byte, pi_interrupt_cause.get_byte(target_byte) & ~value));
    }

    void raise_hollywood_interrupt(HollywoodInterruptCause cause) {
        log_interrupt("InterruptController: raising Hollywood interrupt %s", cause);
        set_hollywood_interrupt_flag(hollywood_interrupt_flag | (1 << cause));
    }

    void recalculate_hollywood_interrupt() {
        if ((hollywood_interrupt_flag & hollywood_interrupt_mask) != 0) {
            log_interrupt("InterruptController: Hollywood interrupt is pending");
            set_interrupt_cause(pi_interrupt_cause | (1 << ProcessorInterfaceInterruptCause.Hollywood));
        } else {
            log_interrupt("InterruptController: Hollywood interrupt is not pending");
            set_interrupt_cause(pi_interrupt_cause & ~(1 << ProcessorInterfaceInterruptCause.Hollywood));
        }
    }

    void raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause cause) {
        log_interrupt("InterruptController: raising Processor Interface interrupt %s", cause);
        set_interrupt_cause(pi_interrupt_cause | (1 << cause));
    }

    void recalculate_processor_interface_interrupt() {
        bool interrupt = ((pi_interrupt_mask & pi_interrupt_cause) != 0);
        log_interrupt("InterruptController: Processor Interface interrupt is %s", interrupt ? "pending" : "not pending");
        broadway.set_exception(ExceptionType.ExternalInterrupt, interrupt);
    }

    void acknowledge_processor_interface_interrupt(ProcessorInterfaceInterruptCause cause) {
        log_interrupt("InterruptController: acknowledging Processor Interface interrupt %s", cause);
        set_interrupt_cause(pi_interrupt_cause & ~(1 << cause));
    }

    void acknowledge_hollywood_interrupt(HollywoodInterruptCause cause) {
        log_interrupt("InterruptController: acknowledging Hollywood interrupt %s", cause);
        set_hollywood_interrupt_flag(hollywood_interrupt_flag & ~(1 << cause));
    }

    void set_interrupt_mask(u32 mask) {
        pi_interrupt_mask = mask;
        log_interrupt("InterruptController: set interrupt mask to %08x", mask);
        recalculate_processor_interface_interrupt();
    }

    void set_interrupt_cause(u32 cause) {
        pi_interrupt_cause = cause;
        log_interrupt("InterruptController: set interrupt cause to %08x", cause);
        recalculate_processor_interface_interrupt();
    }

    void set_hollywood_interrupt_mask(u32 mask) {
        hollywood_interrupt_mask = mask;
        log_interrupt("InterruptController: set Hollywood interrupt mask to %08x", mask);
        recalculate_hollywood_interrupt();
    }

    void set_hollywood_interrupt_flag(u32 flag) {
        hollywood_interrupt_flag = flag;
        log_interrupt("InterruptController: set Hollywood interrupt flag to %08x", flag);
        recalculate_hollywood_interrupt();
    }

    int UNKNOWN_CC003018;
    int UNKNOWN_CC00301C;
    int UNKNOWN_CC003020;

    u8 read_UNKNOWN_CC003018(int target_byte) {
        return UNKNOWN_CC003018.get_byte(target_byte);
    }

    void write_UNKNOWN_CC003018(int target_byte, u8 value) {
        UNKNOWN_CC003018 = UNKNOWN_CC003018.set_byte(target_byte, value);
    }

    u8 read_UNKNOWN_CC00301C(int target_byte) {
        return UNKNOWN_CC00301C.get_byte(target_byte);
    }

    void write_UNKNOWN_CC00301C(int target_byte, u8 value) {
        UNKNOWN_CC00301C = UNKNOWN_CC00301C.set_byte(target_byte, value);
    }

    u8 read_UNKNOWN_CC003020(int target_byte) {
        return UNKNOWN_CC003020.get_byte(target_byte);
    }

    void write_UNKNOWN_CC003020(int target_byte, u8 value) {
        UNKNOWN_CC003020 = UNKNOWN_CC003020.set_byte(target_byte, value);
    }

    void connect_ipc(IPC ipc) {
        this.ipc = ipc;
    }
}