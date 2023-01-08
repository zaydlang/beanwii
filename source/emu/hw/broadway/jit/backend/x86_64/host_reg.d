module emu.hw.broadway.jit.backend.x86_64.host_reg;

import std.conv;
import std.traits;
import std.uni;
import util.log;
import xbyak;

enum HostReg_x86_64 {
    EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI, R8D, R9D, R10D, R11D, R12D, R13D, R14D, R15D,
    SPL, BPL, SIL, DIL,
}

Reg to_xbyak_reg32(HostReg_x86_64 host_reg) {
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
        case HostReg_x86_64.EAX: return al;
        case HostReg_x86_64.ECX: return cl;
        case HostReg_x86_64.EDX: return dl;
        case HostReg_x86_64.EBX: return bl;
        case HostReg_x86_64.ESP: return ah;
        case HostReg_x86_64.EBP: return bpl;
        case HostReg_x86_64.ESI: return sil;
        case HostReg_x86_64.EDI: return dil;
        
        default: error_jit("Could not turn host register %s into an 8-bit xbyak register", host_reg); return al;
    }
}