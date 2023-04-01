module emu.hw.broadway.state;

import util.endian;
import util.log;
import util.number;

struct BroadwayState {
    align(1):
   
    u32[32] gprs;
    PairedSingle[32] ps;

    u32     cr; 
    u32     xer;
    u32     ctr;
    u32     msr;
    u32[8]  gqrs;
    u32     hid0;
    u32     hid2;
    u32     srr0;
    u32     fpsr;
    u32     fpscr;
    u32     l2cr;
    u32     mmcr0;
    u32     mmcr1;
    u32     tbu;
    u32     tbl;
    
    u32     lr;
    u32     pc;
}

struct PairedSingle {
    align(1):
    u64 ps0;
    u64 ps1;
}

public void log_state(BroadwayState* state) {
    if (false) { // mimic dolphin style logs for diffing
        import std.stdio;
        writefln("LOG: fregs PC: 0x%08x CRval: 0x%08x FPSCR: 0x%08x XER: 0x%08x MSR: 0x%08x LR: 0x%08x ",
            state.pc, state.cr, state.fpscr, state.xer, state.msr, state.lr
        );

        writef("LOG: ");
        for (int i = 0; i < 32; i++) {
            writef("%08x ", state.gprs[i]);
        }

        writef(" ");

        for (int i = 0; i < 32; i++) {
            writef("f%02d: %016x %016x ", i, state.ps[i].ps0, state.ps[i].ps1);
        }
        writefln("");
    } else {
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
}