module emu.hw.broadway.state;

import util.endian;
import util.log;
import util.number;

struct BroadwayState {
    align(1):
   
    u32[32] gprs;
    u64[32] fprs;

    u32     cr; 
    u32     xer;
    u32     ctr;
    u32     msr;
    u32[8]  gqrs;
    u32     hid0;
    u32     hid2;

    u32     lr;
    u32     pc;
}

public void log_state(BroadwayState* state) {
    for (int i = 0; i < 32; i += 8) {
        log_broadway("0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x",
            state.gprs[i + 0], state.gprs[i + 1], state.gprs[i + 2], state.gprs[i + 3],
            state.gprs[i + 4], state.gprs[i + 5], state.gprs[i + 6], state.gprs[i + 7]
        );
    }

    log_broadway("cr:  0x%08x", state.cr);
    log_broadway("xer: 0x%08x", state.xer);
    log_broadway("ctr: 0x%08x", state.ctr);

    log_broadway("lr:  0x%08x", state.lr);
    log_broadway("pc:  0x%08x", state.pc);
}