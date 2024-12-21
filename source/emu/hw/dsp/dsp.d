module emu.hw.dsp.dsp;

import emu.hw.broadway.interrupt;
import emu.scheduler;
import util.bitop;
import util.number;
import util.log;

final class DSP {
    enum State {
        Init,
        Ready
    }

    State state;
    Scheduler scheduler;
    InterruptController interrupt_controller;

    this() {
        state = State.Init;
        this.commands_left_to_process_at_init = 10;
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_interrupt_controller(InterruptController interrupt_controller) {
        this.interrupt_controller = interrupt_controller;
    }

    void send_command_to_cpu(u32 command) {
        log_dsp("Sending command to CPU: %08x", command);

        mailbox_from_hi = cast(u16) (command >> 16);
        mailbox_from_lo = cast(u16) (command >> 0);

        if (csr.bit(8)) {
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
            csr |= 1 << 7;
        } else {
            error_dsp("DSP IRQ not enabled????");
        }
    }

    int commands_left_to_process_at_init;
    void process_mailbox_command() {
        log_dsp("Mailbox command: %04x %04x", mailbox_to_lo, mailbox_to_hi);
        final switch (state) {
            case State.Init:
                commands_left_to_process_at_init--;
                if (commands_left_to_process_at_init == 0) {
                    state = State.Ready;
                    scheduler.add_event_relative_to_clock(() => send_command_to_cpu(0xdcd1_0000), 10000);
                    log_dsp("DSP init complete");
                }

                break;

            case State.Ready:
                break;
        }
    }

    u16 mailbox_from_lo;

    u8 read_DSP_MAILBOX_FROM_LOW(int target_byte) {
        return mailbox_from_lo.get_byte(target_byte);
    }

    u16 mailbox_from_hi;

    u8 read_DSP_MAILBOX_FROM_HIGH(int target_byte) {
        if (target_byte == 1 && state == State.Init)
            mailbox_from_hi ^= 0x8000;

        return mailbox_from_hi.get_byte(target_byte);
    }

    u16 mailbox_to_lo;

    u8 read_DSP_MAILBOX_TO_LOW(int target_byte) {
        return mailbox_to_lo.get_byte(target_byte);
    }

    void write_DSP_MAILBOX_TO_LOW(int target_byte, u8 value) {
        mailbox_to_lo = cast(u16) mailbox_from_lo.set_byte(target_byte, value);

        if (target_byte == 1) {
            process_mailbox_command();
        }
    }

    u16 mailbox_to_hi;

    u8 read_DSP_MAILBOX_TO_HIGH(int target_byte) {
        // keep toggling the mailbox value
        if (target_byte == 1)
            mailbox_to_hi ^= 0x8000;

        return mailbox_to_hi.get_byte(target_byte);
    }

    void write_DSP_MAILBOX_TO_HIGH(int target_byte, u8 value) {
        mailbox_to_hi = cast(u16) mailbox_from_hi.set_byte(target_byte, value);
    }

    u32 csr;

    T read_DSP_CSR(T)(int offset) {
        if (offset == 1 || !is(T == u16)) {
            error_dsp("Reading from DSP CSR offset 1 is not supported");
        }

        return cast(T) csr;
    }

    void reset_dsp() {
        // kachow!
        // scheduler.remove_event(complete_internal_aram_dma_event);
    }

    bool aram_dma_in_progress = false;
    ulong complete_internal_aram_dma_event;
    void trigger_internal_aram_dma() {
        log_dsp("Triggering internal ARAM DMA");
        if (aram_dma_in_progress) {
            error_dsp("ARAM DMA already in progress");
        }

        aram_dma_in_progress = true;

        csr |= 1 << 9;

        complete_internal_aram_dma_event = scheduler.add_event_relative_to_clock(&this.complete_internal_aram_dma, 1000);
    }

    void complete_internal_aram_dma() {
        aram_dma_in_progress = false;
        csr &= ~(1 << 9);

        log_dsp("Internal ARAM DMA complete");

        csr |= 1 << 5;
        if (csr.bit(6)) {
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
        }
    }

    void write_DSP_CSR(T)(T value, int offset) {
        if (offset == 1 || !is(T == u16)) {
            error_dsp("Writing to DSP CSR offset 1 is not supported");
        }

        csr = cast(u16) value;
        csr &= ~(1 << 0); // RESET
        csr &= ~(1 << 1); // DSP IRQ

        if (value.bit(2)) {
            // scheduler.remove_event(complete_internal_aram_dma_event);
        }

        log_dsp("DSP CSR: %04x", csr);
        if (value.bit(0)) {
            reset_dsp();
        }

        if (value.bit(3)) {
            csr &= ~(1 << 3);
        }

        if (value.bit(5)) {
            csr &= ~(1 << 5);
        }

        if (value.bit(7)) {
            csr &= ~(1 << 7);
        }

        if (!csr.bit(3) && !csr.bit(5) && !csr.bit(7)) {
            interrupt_controller.acknowledge_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
        }
    }

    u32 aram_mmaddr;

    u8 read_AR_ARAM_MMADDR(int target_byte) {
        return aram_mmaddr.get_byte(target_byte);
    }

    void write_AR_ARAM_MMADDR(int target_byte, u8 value) {
        aram_mmaddr = aram_mmaddr.set_byte(target_byte, value);
    }

    u32 aram_araddr;

    u8 read_AR_ARAM_ARADDR(int target_byte) {
        return aram_araddr.get_byte(target_byte);
    }

    void write_AR_ARAM_ARADDR(int target_byte, u8 value) {
        aram_araddr = aram_araddr.set_byte(target_byte, value);
    }

    u32 aram_size;
    u8 read_ARAM_SIZE(int target_byte) {
        return aram_size.get_byte(target_byte);
    }

    void write_ARAM_SIZE(int target_byte, u8 value) {
        aram_size = aram_size.set_byte(target_byte, value);
    }

    T read_ARAM_SIZE(T)(int offset) {
        if (offset == 1 || !is(T == u16)) {
            error_dsp("Reading from ARAM SIZE offset 1 is not supported");
        }

        return cast(T) aram_size;
    }

    u32 ar_dma_size;

    T read_AR_DMA_SIZE(T)(int offset) {
        if (offset != 0 || !is(T == u32)) {
            error_dsp("Reading from AR DMA SIZE offset 1 is not supported");
        }

        return cast(T) ar_dma_size;
    }

    void write_AR_DMA_SIZE(T)(T value, int offset) {
        if (offset != 0 || !is(T == u32)) {
            error_dsp("Writing to AR DMA SIZE offset 1 is not supported %x %x", offset, T.sizeof);
        }

        aram_size = cast(u32) value;

        log_dsp("DMA from ARAM: %08x -> %08x, size %08x", aram_mmaddr, aram_araddr, aram_size);
        this.trigger_internal_aram_dma();
    }

    u16 ar_dma_start_hi;
    u16 ar_dma_start_lo;

    bool dsp_dma_in_progress = false;

    u8 read_AR_DMA_START_HIGH(int target_byte) {
        return ar_dma_start_hi.get_byte(target_byte);
    }

    void write_AR_DMA_START_HIGH(int target_byte, u8 value) {
        ar_dma_start_hi = cast(u16) ar_dma_start_hi.set_byte(target_byte, value);
    }

    u8 read_AR_DMA_START_LOW(int target_byte) {
        return ar_dma_start_lo.get_byte(target_byte);
    }

    void write_AR_DMA_START_LOW(int target_byte, u8 value) {
        ar_dma_start_lo = cast(u16) ar_dma_start_lo.set_byte(target_byte, value);
    }

    u16 ar_dma_cnt;

    T read_AR_DMA_CNT(T)(int offset) {
        if (offset != 0 || !is(T == u16)) {
            error_dsp("Reading from AR DMA SIZE offset 1 is not supported");
        }

        return cast(T) ar_dma_cnt;
    }

    void write_AR_DMA_CNT(T)(T value, int offset) {
        if (offset != 0 || !is(T == u16)) {
            error_dsp("Writing to AR DMA SIZE offset 1 is not supported");
        }

        ar_dma_cnt = cast(u16) value;

        log_dsp("DMA from ARAM: %08x -> %08x, size %08x", aram_mmaddr, aram_araddr, aram_size);
        if (ar_dma_cnt.bit(15)) this.trigger_dsp_dma();
    }

    u8 read_DSP_DMA_BYTES_LEFT(int target_byte) {
        auto cycles_left = scheduler.get_current_time_relative_to_cpu() - dma_start_time;
        auto bytes_left = (32 * (ar_dma_cnt & 0x7fff)) - (cycles_left / CYCLES_PER_BYTE);
        if (bytes_left < 0) bytes_left = 0;

        return bytes_left.get_byte(target_byte);
    }

    ulong dma_start_time;
    enum CYCLES_PER_BYTE = 3;
    void trigger_dsp_dma() {
        log_dsp("Triggering DSP DMA");
        if (dsp_dma_in_progress) {
            error_dsp("DSP DMA already in progress");
        }

        dsp_dma_in_progress = true;
        int length = 32 * (ar_dma_cnt & 0x7fff);
        dma_start_time = scheduler.get_current_time_relative_to_cpu();
        scheduler.add_event_relative_to_clock(&this.complete_dsp_dma, length * CYCLES_PER_BYTE);
    }

    void complete_dsp_dma() {
        dsp_dma_in_progress = false;

        if (csr.bit(4)) {
            csr |= 1 << 3;
            log_dsp("DSP DMA complete");
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
        }
    }
}
