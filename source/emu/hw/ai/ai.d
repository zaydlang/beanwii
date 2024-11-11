module emu.hw.ai.ai;

import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.log;
import util.number;

final class AudioInterface {
    this() {

    }

    u32 ai_control;
    void write_AI_CONTROL(int target_byte, u8 value) {
        ai_control = ai_control.set_byte(target_byte, value);
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
}