module emu.hw.dsp.jit.emission.config;

import util.number;

struct DspCodeConfig {
    bool sr_SXM;

    u32 to_bitfield() {
        u32 bitfield = 0;
        if (sr_SXM) bitfield |= 1;
        return bitfield;
    }
}