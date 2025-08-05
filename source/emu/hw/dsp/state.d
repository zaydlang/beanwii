module emu.hw.dsp.state;

import util.number;

struct DspState {
    u16[32] g;
    u16[32] r;
    u16[4]  ar;
    u16[4]  ix;
    u16[4]  st;
    u16[2]  ach;
    u16[2]  acm;
    u16[2]  acl;
    u16[2]  axl;
    u16[2]  axh;
    u16     config;
    u16     sr;
    u16     prodl;
    u16     prodm1;
    u16     prodh;
    u16     prodm2;

    u16     addressing_register;
}