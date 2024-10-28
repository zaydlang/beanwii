module emu.hw.broadway.jit.emission.guest_reg;

import std.conv;
import std.uni;

enum GuestReg {
    R0,  R1,  R2,  R3,  R4,  R5,  R6,  R7,  R8,  R9,  R10, R11, R12, R13, R14, R15,
    R16, R17, R18, R19, R20, R21, R22, R23, R24, R25, R26, R27, R28, R29, R30, R31,

    F0,  F1,  F2,  F3,  F4,  F5,  F6,  F7,  F8,  F9,  F10, F11, F12, F13, F14, F15,
    F16, F17, F18, F19, F20, F21, F22, F23, F24, F25, F26, F27, F28, F29, F30, F31,

    PS0_0, PS0_1, PS1_0, PS1_1, PS2_0, PS2_1, PS3_0, PS3_1, PS4_0, PS4_1, PS5_0, PS5_1, PS6_0, PS6_1, PS7_0, PS7_1,
    PS8_0, PS8_1, PS9_0, PS9_1, PS10_0, PS10_1, PS11_0, PS11_1, PS12_0, PS12_1, PS13_0, PS13_1, PS14_0, PS14_1, PS15_0, PS15_1,
    PS16_0, PS16_1, PS17_0, PS17_1, PS18_0, PS18_1, PS19_0, PS19_1, PS20_0, PS20_1, PS21_0, PS21_1, PS22_0, PS22_1, PS23_0, PS23_1,
    PS24_0, PS24_1, PS25_0, PS25_1, PS26_0, PS26_1, PS27_0, PS27_1, PS28_0, PS28_1, PS29_0, PS29_1, PS30_0, PS30_1, PS31_0, PS31_1,

    CR,

    XER,
    CTR,
    MSR,

    GQR0, GQR1, GQR2, GQR3, GQR4, GQR5, GQR6, GQR7,

    SRR0,
    FPSR,
    FPSCR,
    MMCR0,
    MMCR1,
    PMC1,
    PMC2,
    PMC3,
    PMC4,

    L2CR,

    HID0,
    HID2,
    HID4,

    TBL,
    TBU,

    LR,
    PC,
}

public GuestReg to_gpr(int reg) {
    return cast(GuestReg) reg + GuestReg.R0;
}

public GuestReg to_fpr(int reg) {
    return cast(GuestReg) reg + GuestReg.F0;
}

public GuestReg to_gqr(int reg) {
    return cast(GuestReg) reg + GuestReg.GQR0;
}

public GuestReg to_ps(int reg) {
    return cast(GuestReg) reg + GuestReg.PS0_0;
}

public GuestReg to_ps0(int reg) {
    return cast(GuestReg) (reg * 2) + GuestReg.PS0_0;
}

public GuestReg to_ps1(int reg) {
    return cast(GuestReg) (reg * 2) + GuestReg.PS0_1;
}

public string to_string(GuestReg reg) {
    return std.conv.to!string(reg).toLower();
}

public size_t get_reg_offset(GuestReg reg) {
    import emu.hw.broadway.state;

    switch (reg) {
        case GuestReg.R0:    .. case GuestReg.R31:    return BroadwayState.gprs.offsetof + (reg - GuestReg.R0) * 4;
        case GuestReg.F0:    .. case GuestReg.F31:    return BroadwayState.ps.offsetof   + (reg - GuestReg.F0) * 16;
        case GuestReg.GQR0:  .. case GuestReg.GQR7:   return BroadwayState.gqrs.offsetof + (reg - GuestReg.GQR0) * 4;
        case GuestReg.PS0_0: .. case GuestReg.PS31_1: return BroadwayState.ps.offsetof   + (reg - GuestReg.PS0_0) * 8;
    
        case GuestReg.CR:    return BroadwayState.cr.offsetof;
        case GuestReg.XER:   return BroadwayState.xer.offsetof;
        case GuestReg.CTR:   return BroadwayState.ctr.offsetof;
        case GuestReg.MSR:   return BroadwayState.msr.offsetof;
        case GuestReg.HID0:  return BroadwayState.hid0.offsetof;
        case GuestReg.HID2:  return BroadwayState.hid2.offsetof;
        case GuestReg.HID4:  return BroadwayState.hid4.offsetof;
        case GuestReg.SRR0:  return BroadwayState.srr0.offsetof;
        case GuestReg.FPSR:  return BroadwayState.fpsr.offsetof;
        case GuestReg.FPSCR: return BroadwayState.fpscr.offsetof;
        case GuestReg.L2CR:  return BroadwayState.l2cr.offsetof;
        case GuestReg.TBU:   return BroadwayState.tbu.offsetof;
        case GuestReg.TBL:   return BroadwayState.tbl.offsetof;
        case GuestReg.MMCR0: return BroadwayState.mmcr0.offsetof;
        case GuestReg.MMCR1: return BroadwayState.mmcr1.offsetof;
        case GuestReg.PMC1:  return BroadwayState.pmc1.offsetof;
        case GuestReg.PMC2:  return BroadwayState.pmc2.offsetof;
        case GuestReg.PMC3:  return BroadwayState.pmc3.offsetof;
        case GuestReg.PMC4:  return BroadwayState.pmc4.offsetof;
        case GuestReg.LR:    return BroadwayState.lr.offsetof;
        case GuestReg.PC:    return BroadwayState.pc.offsetof;

        default: assert(0);
    }
}