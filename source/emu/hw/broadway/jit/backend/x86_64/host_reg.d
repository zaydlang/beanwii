module emu.hw.broadway.jit.backend.x86_64.host_reg;

import std.conv;
import std.traits;
import std.uni;
import util.log;
import xbyak;

enum HostReg_x86_64 {
    RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8, R9, R10, R11, R12, R13, R14, R15,
    XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7,
    SPL, BPL, SIL, DIL,
}

Reg to_xbyak_reg64(HostReg_x86_64 host_reg) {
    import std.format;

    final switch (host_reg) {
        static foreach (enum H; EnumMembers!HostReg_x86_64) {
            case H:
                mixin("return %s;".format(to!string(H).toLower()));
        }
    }
}

Reg8 to_xbyak_reg8(HostReg_x86_64 host_reg) {
    import std.format;

    switch (host_reg) {
        case HostReg_x86_64.RAX: return al;
        case HostReg_x86_64.RCX: return cl;
        case HostReg_x86_64.RDX: return dl;
        case HostReg_x86_64.RBX: return bl;
        case HostReg_x86_64.RSP: return ah;
        case HostReg_x86_64.RBP: return bpl;
        case HostReg_x86_64.RSI: return sil;
        case HostReg_x86_64.RDI: return dil;
        case HostReg_x86_64.R8:  return r8b;
        case HostReg_x86_64.R9:  return r9b;
        case HostReg_x86_64.R10: return r10b;
        case HostReg_x86_64.R11: return r11b;
        case HostReg_x86_64.R12: return r12b;
        case HostReg_x86_64.R13: return r13b;
        case HostReg_x86_64.R14: return r14b;
        case HostReg_x86_64.R15: return r15b;
        
        default: error_jit("Could not turn host register %s into an 8-bit xbyak register", host_reg); return al;
    }
}