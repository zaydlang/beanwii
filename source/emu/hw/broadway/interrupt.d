module emu.hw.broadway.interrupt;

import emu.hw.broadway.cpu;
import emu.hw.broadway.exception_type;
import util.bitop;
import util.log;
import util.number;

enum HollywoodInterruptCause {
    IPC = 30,
}

enum ProcessorInterfaceInterruptCause {
    Hollywood = 14,
}

final class InterruptController {
    this() {
        hollywood_interrupt_mask = 1 << HollywoodInterruptCause.IPC;
    }

    Broadway broadway;
    
    void connect_cpu(Broadway broadway) {
        this.broadway = broadway;
    }

    u32 pi_interrupt_mask;

    u8 read_INTERRUPT_MASK(int target_byte) {
        return pi_interrupt_mask.get_byte(target_byte);
    }

    void write_INTERRUPT_MASK(int target_byte, u8 value) {
        pi_interrupt_mask = pi_interrupt_mask.set_byte(target_byte, value);
    }

    u32 hollywood_interrupt_flag;

    u8 read_HW_PPCIRQFLAG(int target_byte) {
        return hollywood_interrupt_flag.get_byte(target_byte);
    }

    void write_HW_PPCIRQFLAG(int target_byte, u8 value) {
        log_interrupt("HW_PPCIRQFLAG[%d] = %02x", target_byte, value);
        if (target_byte == 3 && value & 0x40) {
            log_interrupt("wtf");
            pi_interrupt_cause = 0;
        }

        hollywood_interrupt_flag = hollywood_interrupt_flag.set_byte(
            target_byte, hollywood_interrupt_flag.get_byte(target_byte) & ~value);
        maybe_raise_hollywood_interrupt();
    }

    u32 hollywood_interrupt_mask;

    u8 read_HW_PPCIRQMASK(int target_byte) {
        return hollywood_interrupt_mask.get_byte(target_byte);
    }

    void write_HW_PPCIRQMASK(int target_byte, u8 value) {
        hollywood_interrupt_mask = hollywood_interrupt_mask.set_byte(target_byte, value);
        maybe_raise_hollywood_interrupt();
    }

    u8 read_UNKNOWN_CC00302C(int target_byte) {
        return 0x20000000.get_byte(target_byte);
    }

    void write_UNKNOWN_CC00302C(int target_byte, u8 value) {
        error_interrupt("Write to unknown interrupt controller register 0xCC00302C: %02x", value);
    }

    u32 pi_interrupt_cause;

    u8 read_INTERRUPT_CAUSE(int target_byte) {
        return pi_interrupt_cause.get_byte(target_byte);
    }

    void write_INTERRUPT_CAUSE(int target_byte, u8 value) {
        pi_interrupt_cause = pi_interrupt_cause.set_byte(target_byte, pi_interrupt_cause.get_byte(target_byte) & ~value);
    }

    void raise_hollywood_interrupt(HollywoodInterruptCause cause) {
        log_interrupt("InterruptController: raising Hollywood interrupt %s", cause);
        hollywood_interrupt_flag |= (1 << cause);
        maybe_raise_hollywood_interrupt();
    }

    void maybe_raise_hollywood_interrupt() {
        log_interrupt("InterruptController: maybe raising Hollywood interrupt: flag=%08x mask=%08x",
            hollywood_interrupt_flag, hollywood_interrupt_mask);
        if ((hollywood_interrupt_flag & hollywood_interrupt_mask) != 0) {
            log_interrupt("InterruptController: raising Hollywood interrupt");
            pi_interrupt_cause |= (1 << ProcessorInterfaceInterruptCause.Hollywood);
            maybe_raise_processor_interface_interrupt();
        }
    }

    void raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause cause) {
        log_interrupt("InterruptController: raising Processor Interface interrupt %s", cause);
        pi_interrupt_cause |= (1 << cause);
        maybe_raise_processor_interface_interrupt();
    }

    void maybe_raise_processor_interface_interrupt() {
        if ((pi_interrupt_mask & pi_interrupt_cause) != 0) {
            if (broadway.state.msr.bit(15)) {
                log_interrupt("InterruptController: raising Processor Interface interrupt");
                broadway.raise_exception(ExceptionType.ExternalInterrupt);
            }
        }
    }
}