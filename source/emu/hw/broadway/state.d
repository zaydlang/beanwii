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
    u32     hid4;
    u32     srr0;
    u32     srr1;
    u32     fpsr;
    u32     fpscr;
    u32     l2cr;
    u32     mmcr0;
    u32     mmcr1;
    u32     pmc1;
    u32     pmc2;
    u32     pmc3;
    u32     pmc4;
    u32     tbu;
    u32     tbl;
    u32[8]  ibat_low;
    u32[8]  ibat_high;
    u32[8]  dbat_low;
    u32[8]  dbat_high;
    u32[16] sr;
    u32     sprg0;
    u32     sprg1;
    u32     sprg2;
    u32     sprg3;
    u32     dec;
    u32     dar;
    u32     wpar;

    u32     lr;
    u32     pc;
    
    bool    halted;
    bool    icache_flushed;
    u32     icbi_address;
}

struct PairedSingle {
    align(1):
    u64 ps0;
    u64 ps1;
}

public void log_state(BroadwayState* state) {
        import std.stdio;
    if (false) { // mimic dolphin style logs for diffing
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
            writefln("0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x",
                state.gprs[i + 0], state.gprs[i + 1], state.gprs[i + 2], state.gprs[i + 3],
                state.gprs[i + 4], state.gprs[i + 5], state.gprs[i + 6], state.gprs[i + 7]
            );
        }

        // fprs
        for (int i = 0; i < 32; i += 2) {
            writefln("f%02d: 0x%08x (%f) 0x%08x (%f) 0x%08x (%f) 0x%08x (%f)",
                i + 0,
                state.ps[i + 0].ps0, *(cast(double*)&state.ps[i + 0].ps0),
                state.ps[i + 0].ps1, *(cast(double*)&state.ps[i + 0].ps1),
                state.ps[i + 1].ps0, *(cast(double*)&state.ps[i + 1].ps0),
                state.ps[i + 1].ps1, *(cast(double*)&state.ps[i + 1].ps1)
            );
        }

        writefln("cr:  0x%08x", state.cr);
        writefln("xer: 0x%08x", state.xer);
        writefln("ctr: 0x%08x", state.ctr);
        writefln("hid2: 0x%08x", state.hid2);

        for (int i = 0; i < 8; i += 2) {
            writefln("gqr%02d: 0x%08x 0x%08x", i + 0, state.gqrs[i + 0], state.gqrs[i + 1]);
        }

        writefln("lr:  0x%08x", state.lr);
        writefln("pc:  0x%08x", state.pc);
    }
}