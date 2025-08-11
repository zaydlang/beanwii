module emu.hw.dsp.state;

import util.number;

struct DspState {
    u16[32] reg;

    u16 pc;
}