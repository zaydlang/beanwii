module emu.hw.pe.pe;

import bindbc.opengl;
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
    }

    InterruptController interrupt_controller;
    void connect_interrupt_controller(InterruptController interrupt_controller) {
        this.interrupt_controller = interrupt_controller;
    }

    void raise_finish_interrupt() {
        log_pe("PE finish interrupt");
        if (pe_irq.bit(1)) {
            log_pe("PE finish interrupt");
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.PeFinish);
        }
    }

    u32 z_config;
    void write_Z_CONFIG(int target_byte, u8 value) {

    }

    u8 read_Z_CONFIG(int target_byte) {
        return z_config.get_byte(target_byte);
    }

    u32 alpha_config;
    
    bool boolean_blending_enable;
    bool arithmetic_blending_enable;
    bool dither_enable;
    bool color_update_enable;
    bool alpha_update_enable;
    int blend_destination;
    int blend_source;
    bool subtractive_additive_toggle;
    int blend_operator;
    
    void write_ALPHA_CONFIG(int target_byte, u8 value) {
        log_pe("ALPHA_CONFIG: %d %x", target_byte, value);
        alpha_config = alpha_config.set_byte(target_byte, value);
        
        boolean_blending_enable       = alpha_config.bit(0);
        arithmetic_blending_enable    = alpha_config.bit(1);
        dither_enable                 = alpha_config.bit(2);
        color_update_enable           = alpha_config.bit(3);
        alpha_update_enable           = alpha_config.bit(4);
        blend_destination             = alpha_config.bits(5, 7);
        blend_source                  = alpha_config.bits(8, 10);
        subtractive_additive_toggle   = alpha_config.bit(11);
        blend_operator                = alpha_config.bits(12, 15);
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
        log_pe("PE_IRQ: %d %x", target_byte, value);
        if (target_byte == 0 && value.bit(3)) {
            interrupt_controller.acknowledge_processor_interface_interrupt(ProcessorInterfaceInterruptCause.PeFinish);
            value &= ~0x08;
        }

        if (target_byte == 0 && value.bit(2)) {
            interrupt_controller.acknowledge_processor_interface_interrupt(ProcessorInterfaceInterruptCause.PeToken);
            value &= ~0x04;
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
        log_pe("PE_TOKEN: %d %x %x %x", target_byte, pe_token.get_byte(target_byte), interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return pe_token.get_byte(target_byte);
    }

    void raise_token_interrupt(u16 token) {
        pe_token = token;

        if (pe_irq.bit(0)) {
            log_pe("PE token interrupt: %04x", token);
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.PeToken);
        }
    }

    u16 bbox_left;
    void write_BBOX_LEFT(int target_byte, u8 value) {
        bbox_left = cast(u16) bbox_left.set_byte(target_byte, value);
    }

    u8 read_BBOX_LEFT(int target_byte) {
        return bbox_left.get_byte(target_byte);
    }

    u16 bbox_right;
    void write_BBOX_RIGHT(int target_byte, u8 value) {
        bbox_right = cast(u16) bbox_right.set_byte(target_byte, value);
    }

    u8 read_BBOX_RIGHT(int target_byte) {
        return bbox_right.get_byte(target_byte);
    }

    u16 bbox_top;
    void write_BBOX_TOP(int target_byte, u8 value) {
        bbox_top = cast(u16) bbox_top.set_byte(target_byte, value);
    }

    u8 read_BBOX_TOP(int target_byte) {
        return bbox_top.get_byte(target_byte);
    }

    u16 bbox_bottom;
    void write_BBOX_BOTTOM(int target_byte, u8 value) {
        bbox_bottom = cast(u16) bbox_bottom.set_byte(target_byte, value);
    }

    u8 read_BBOX_BOTTOM(int target_byte) {
        return bbox_bottom.get_byte(target_byte);
    }
}