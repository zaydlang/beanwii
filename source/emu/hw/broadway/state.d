module emu.hw.broadway.state;

import util.endian;
import util.number;

struct BroadwayState {
    align(1):
   
    u32_be[32] gprs;
    u32        pc;
}