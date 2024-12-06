module emu.hw.ai.ai;

import emu.hw.memory.strategy.memstrategy;
import emu.hw.broadway.interrupt;
import emu.scheduler;
import util.bitop;
import util.log;
import util.number;

final class AudioInterface {
    this() {

    }

    Scheduler scheduler;
    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    InterruptController interrupt_controller;
    void connect_interrupt_controller(InterruptController interrupt_controller) {
        this.interrupt_controller = interrupt_controller;
    }

    ulong audio_sampling_event_id;
    int sample_rate_khz;

    u32 ai_control;
    void write_AI_CONTROL(int target_byte, u8 value) {
        ai_control = ai_control.set_byte(target_byte, value);

        ai_control &= ~(1 << 5);

        if (target_byte == 0) {
            sample_rate_khz = value.bit(1) ? 32 : 48;
        
            if (value.bit(0)) {
                reschedule_audio_sampling();
            } else {
                scheduler.remove_event(audio_sampling_event_id);
            }

            if (value.bit(3)) {
                interrupt_controller.acknowledge_processor_interface_interrupt(ProcessorInterfaceInterruptCause.AI);
            }

            if (value.bit(5)) {
                aiscnt = 0;
            }
        }

    }

    void reschedule_audio_sampling() {
        auto num_cycles = 33_513_982 / (sample_rate_khz * 1000);
        scheduler.remove_event(audio_sampling_event_id);

        audio_sampling_event_id = scheduler.add_event_relative_to_clock(&this.sample_audio, num_cycles);
    }

    void sample_audio() {
        auto num_cycles = 33_513_982 / (sample_rate_khz * 1000);
        scheduler.remove_event(audio_sampling_event_id);

        audio_sampling_event_id = scheduler.add_event_relative_to_self(&this.sample_audio, num_cycles);

        aiscnt++;

        log_ai("Sampling audio %x %x", aiscnt, aiit);

        if (aiscnt == aiit) {
            ai_control |= 1 << 3;
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.AI);
        }
    }

    u8 read_AI_CONTROL(int target_byte) {
        return ai_control.get_byte(target_byte);
    }

    u32 dsp_control_status;
    void write_DSP_CONTROL_STATUS(int target_byte, u8 value) {
        dsp_control_status = dsp_control_status.set_byte(target_byte, value);
    }

    u8 read_DSP_CONTROL_STATUS(int target_byte) {
        return dsp_control_status.get_byte(target_byte);
    }

    u32 hw_pllaiext;
    void write_HW_PLLAIEXT(int target_byte, u8 value) {
        hw_pllaiext = hw_pllaiext.set_byte(target_byte, value);
    }

    u8 read_HW_PLLAIEXT(int target_byte) {
        return hw_pllaiext.get_byte(target_byte);
    }

    u32 hw_pllai;
    void write_HW_PLLAI(int target_byte, u8 value) {
        hw_pllai = hw_pllai.set_byte(target_byte, value);
    }

    u8 read_HW_PLLAI(int target_byte) {
        return hw_pllai.get_byte(target_byte);
    }

    u32 aivr;
    void write_AIVR(int target_byte, u8 value) {
        aivr = aivr.set_byte(target_byte, value);
    }

    u8 read_AIVR(int target_byte) {
        return aivr.get_byte(target_byte);
    }

    u32 aiscnt;
    void write_AISCNT(int target_byte, u8 value) {
        aiscnt = aiscnt.set_byte(target_byte, value);
    }

    u8 read_AISCNT(int target_byte) {
        // TODO:
        aiscnt++;
        return aiscnt.get_byte(target_byte);
    }

    u32 aiit;
    void write_AIIT(int target_byte, u8 value) {
        aiit = aiit.set_byte(target_byte, value);
    }

    u8 read_AIIT(int target_byte) {
        return aiit.get_byte(target_byte);
    }
}