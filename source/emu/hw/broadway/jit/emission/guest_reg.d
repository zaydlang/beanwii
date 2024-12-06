module emu.hw.broadway.jit.emission.guest_reg;

import std.conv;
import std.uni;
import util.log;

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
    SRR1,
    FPSR,
    FPSCR,
    MMCR0,
    MMCR1,
    PMC1,
    PMC2,
    PMC3,
    PMC4,
    SPRG0,
    SPRG1,
    SPRG2,
    SPRG3,

    IBAT0U, IBAT0L, IBAT1U, IBAT1L, IBAT2U, IBAT2L, IBAT3U, IBAT3L, IBAT4U, IBAT4L, IBAT5U, IBAT5L, IBAT6U, IBAT6L, IBAT7U, IBAT7L,
    DBAT0U, DBAT0L, DBAT1U, DBAT1L, DBAT2U, DBAT2L, DBAT3U, DBAT3L, DBAT4U, DBAT4L, DBAT5U, DBAT5L, DBAT6U, DBAT6L, DBAT7U, DBAT7L,

    DEC,

    DAR,

    L2CR,

    HID0,
    HID2,
    HID4,

    TBL,
    TBU,

    WPAR,

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
    return to_ps0(reg);
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
        case GuestReg.SRR1:  return BroadwayState.srr1.offsetof;
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

        case GuestReg.IBAT0U: return BroadwayState.ibat_low.offsetof + 0 * 4;
        case GuestReg.IBAT0L: return BroadwayState.ibat_high.offsetof + 0 * 4;
        case GuestReg.IBAT1U: return BroadwayState.ibat_low.offsetof + 1 * 4;
        case GuestReg.IBAT1L: return BroadwayState.ibat_high.offsetof + 1 * 4;
        case GuestReg.IBAT2U: return BroadwayState.ibat_low.offsetof + 2 * 4;
        case GuestReg.IBAT2L: return BroadwayState.ibat_high.offsetof + 2 * 4;
        case GuestReg.IBAT3U: return BroadwayState.ibat_low.offsetof + 3 * 4;
        case GuestReg.IBAT3L: return BroadwayState.ibat_high.offsetof + 3 * 4;
        case GuestReg.IBAT4U: return BroadwayState.ibat_low.offsetof + 4 * 4;
        case GuestReg.IBAT4L: return BroadwayState.ibat_high.offsetof + 4 * 4;
        case GuestReg.IBAT5U: return BroadwayState.ibat_low.offsetof + 5 * 4;
        case GuestReg.IBAT5L: return BroadwayState.ibat_high.offsetof + 5 * 4;
        case GuestReg.IBAT6U: return BroadwayState.ibat_low.offsetof + 6 * 4;
        case GuestReg.IBAT6L: return BroadwayState.ibat_high.offsetof + 6 * 4;
        case GuestReg.IBAT7U: return BroadwayState.ibat_low.offsetof + 7 * 4;
        case GuestReg.IBAT7L: return BroadwayState.ibat_high.offsetof + 7 * 4;
        
        case GuestReg.DBAT0U: return BroadwayState.dbat_low.offsetof + 0 * 4;
        case GuestReg.DBAT0L: return BroadwayState.dbat_high.offsetof + 0 * 4;
        case GuestReg.DBAT1U: return BroadwayState.dbat_low.offsetof + 1 * 4;
        case GuestReg.DBAT1L: return BroadwayState.dbat_high.offsetof + 1 * 4;
        case GuestReg.DBAT2U: return BroadwayState.dbat_low.offsetof + 2 * 4;
        case GuestReg.DBAT2L: return BroadwayState.dbat_high.offsetof + 2 * 4;
        case GuestReg.DBAT3U: return BroadwayState.dbat_low.offsetof + 3 * 4;
        case GuestReg.DBAT3L: return BroadwayState.dbat_high.offsetof + 3 * 4;
        case GuestReg.DBAT4U: return BroadwayState.dbat_low.offsetof + 4 * 4;
        case GuestReg.DBAT4L: return BroadwayState.dbat_high.offsetof + 4 * 4;
        case GuestReg.DBAT5U: return BroadwayState.dbat_low.offsetof + 5 * 4;
        case GuestReg.DBAT5L: return BroadwayState.dbat_high.offsetof + 5 * 4;
        case GuestReg.DBAT6U: return BroadwayState.dbat_low.offsetof + 6 * 4;
        case GuestReg.DBAT6L: return BroadwayState.dbat_high.offsetof + 6 * 4;
        case GuestReg.DBAT7U: return BroadwayState.dbat_low.offsetof + 7 * 4;
        case GuestReg.DBAT7L: return BroadwayState.dbat_high.offsetof + 7 * 4;
        
        case GuestReg.SPRG0: return BroadwayState.sprg0.offsetof;
        case GuestReg.SPRG1: return BroadwayState.sprg1.offsetof;
        case GuestReg.SPRG2: return BroadwayState.sprg2.offsetof;
        case GuestReg.SPRG3: return BroadwayState.sprg3.offsetof;

        case GuestReg.DEC:   return BroadwayState.dec.offsetof;
        case GuestReg.DAR:   return BroadwayState.dar.offsetof;

        case GuestReg.WPAR:  return BroadwayState.wpar.offsetof;

        default: assert(0);
    }
}

public GuestReg get_spr_from_encoding(int encoding) {
    switch (encoding) {
        case 9:    return GuestReg.CTR;
        case 8:    return GuestReg.LR;
        case 1:    return GuestReg.XER;
        case 26:   return GuestReg.SRR0;
        case 27:   return GuestReg.SRR1;
        case 912:  return GuestReg.GQR0;
        case 913:  return GuestReg.GQR1;
        case 914:  return GuestReg.GQR2;
        case 915:  return GuestReg.GQR3;
        case 916:  return GuestReg.GQR4;
        case 917:  return GuestReg.GQR5;
        case 918:  return GuestReg.GQR6;
        case 919:  return GuestReg.GQR7;
        case 1008: return GuestReg.HID0;
        case 920:  return GuestReg.HID2;
        case 1011: return GuestReg.HID4;
        case 1017: return GuestReg.L2CR;
        case 952:  return GuestReg.MMCR0;
        case 956:  return GuestReg.MMCR1;
        case 953:  return GuestReg.PMC1;
        case 954:  return GuestReg.PMC2;
        case 957:  return GuestReg.PMC3;
        case 958:  return GuestReg.PMC4;
        case 528:  return GuestReg.IBAT0U;
        case 529:  return GuestReg.IBAT0L;
        case 530:  return GuestReg.IBAT1U;
        case 531:  return GuestReg.IBAT1L;
        case 532:  return GuestReg.IBAT2U;
        case 533:  return GuestReg.IBAT2L;
        case 534:  return GuestReg.IBAT3U;
        case 535:  return GuestReg.IBAT3L;
        case 536:  return GuestReg.DBAT0U;
        case 537:  return GuestReg.DBAT0L;
        case 538:  return GuestReg.DBAT1U;
        case 539:  return GuestReg.DBAT1L;
        case 540:  return GuestReg.DBAT2U;
        case 541:  return GuestReg.DBAT2L;
        case 542:  return GuestReg.DBAT3U;
        case 543:  return GuestReg.DBAT3L;
        case 560:  return GuestReg.IBAT4U;
        case 561:  return GuestReg.IBAT4L;
        case 562:  return GuestReg.IBAT5U;
        case 563:  return GuestReg.IBAT5L;
        case 564:  return GuestReg.IBAT6U;
        case 565:  return GuestReg.IBAT6L;
        case 566:  return GuestReg.IBAT7U;
        case 567:  return GuestReg.IBAT7L;
        case 568:  return GuestReg.DBAT4U;
        case 569:  return GuestReg.DBAT4L;
        case 570:  return GuestReg.DBAT5U;
        case 571:  return GuestReg.DBAT5L;
        case 572:  return GuestReg.DBAT6U;
        case 573:  return GuestReg.DBAT6L;
        case 574:  return GuestReg.DBAT7U;
        case 575:  return GuestReg.DBAT7L;
        case 272:  return GuestReg.SPRG0;
        case 273:  return GuestReg.SPRG1;
        case 274:  return GuestReg.SPRG2;
        case 275:  return GuestReg.SPRG3;
        case 22:   return GuestReg.DEC;
        case 19:   return GuestReg.DAR;
        case 284:  return GuestReg.TBL;
        case 285:  return GuestReg.TBU;
        case 921:  return GuestReg.WPAR;

        default: 
            error_broadway("Unknown SPR: %d (0x%x)", encoding, encoding);
            assert(0);
    }
}