module emu.hw.pe.pe;

import emu.hw.broadway.interrupt;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.log;
import util.number;

final class PixelEngine {
    Scheduler scheduler;
    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;

        scheduler.add_event_relative_to_clock(&this.pe_finish, 33_513_982 / 60);
    }

    InterruptController interrupt_controller;
    void connect_interrupt_controller(InterruptController interrupt_controller) {
        this.interrupt_controller = interrupt_controller;
    }

    void pe_finish() {
        if (pe_irq.bit(1)) {
            log_pe("PE finish interrupt");
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.PeFinish);
        }

        log_pe("PE finish");
        scheduler.add_event_relative_to_self(&this.pe_finish, 33_513_982 / 60);
    }

    u32 z_config;
    void write_Z_CONFIG(int target_byte, u8 value) {
        z_config = z_config.set_byte(target_byte, value);
    }

    u8 read_Z_CONFIG(int target_byte) {
        return z_config.get_byte(target_byte);
    }

    u32 alpha_config;
    void write_ALPHA_CONFIG(int target_byte, u8 value) {
        alpha_config = alpha_config.set_byte(target_byte, value);
    }

    u8 read_ALPHA_CONFIG(int target_byte) {
        return alpha_config.get_byte(target_byte);
    }

    u32 destination_alpha;
    void write_DESTINATION_ALPHA(int target_byte, u8 value) {
        destination_alpha = destination_alpha.set_byte(target_byte, value);
    }

    u8 read_DESTINATION_ALPHA(int target_byte) {
        return destination_alpha.get_byte(target_byte);
    }

    u32 alpha_mode;
    void write_ALPHA_MODE(int target_byte, u8 value) {
        alpha_mode = alpha_mode.set_byte(target_byte, value);
    }

    u8 read_ALPHA_MODE(int target_byte) {
        return alpha_mode.get_byte(target_byte);
    }

    u32 alpha_read;
    void write_ALPHA_READ(int target_byte, u8 value) {
        alpha_read = alpha_read.set_byte(target_byte, value);
    }

    u8 read_ALPHA_READ(int target_byte) {
        return alpha_read.get_byte(target_byte);
    }

    u32 pe_irq;
    void write_PE_IRQ(int target_byte, u8 value) {
        if (target_byte == 0 && value.bit(3)) {
            interrupt_controller.acknowledge_processor_interface_interrupt(ProcessorInterfaceInterruptCause.PeFinish);
            value &= ~0x08;
        }

        pe_irq = pe_irq.set_byte(target_byte, value);
    }

    u8 read_PE_IRQ(int target_byte) {
        return pe_irq.get_byte(target_byte);
    }

    u32 pe_token;
    void write_PE_TOKEN(int target_byte, u8 value) {
        pe_token = pe_token.set_byte(target_byte, value);
    }

    u8 read_PE_TOKEN(int target_byte) {
        return pe_token.get_byte(target_byte);
    }
}