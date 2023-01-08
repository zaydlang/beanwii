module emu.hw.broadway.state;

import util.endian;
import util.number;

struct BroadwayState {
    align(1):
   
    u32[32] gprs;

    u32     cr; 
    u32     xer;

    u32     lr;
    u32     pc;
}