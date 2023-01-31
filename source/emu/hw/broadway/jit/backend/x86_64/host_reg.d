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

Reg32 to_xbyak_reg32(HostReg_x86_64 host_reg) {
    import std.format;

    switch (host_reg) {
        case HostReg_x86_64.RAX: return rax.cvt32();
        case HostReg_x86_64.RCX: return rcx.cvt32();
        case HostReg_x86_64.RDX: return rdx.cvt32();
        case HostReg_x86_64.RBX: return rbx.cvt32();
        case HostReg_x86_64.RSP: return rsp.cvt32();
        case HostReg_x86_64.RBP: return rbp.cvt32();
        case HostReg_x86_64.RSI: return rsi.cvt32();
        case HostReg_x86_64.RDI: return rdi.cvt32();
        case HostReg_x86_64.R8:  return r8.cvt32();
        case HostReg_x86_64.R9:  return r9.cvt32();
        case HostReg_x86_64.R10: return r10.cvt32();
        case HostReg_x86_64.R11: return r11.cvt32();
        case HostReg_x86_64.R12: return r12.cvt32();
        case HostReg_x86_64.R13: return r13.cvt32();
        case HostReg_x86_64.R14: return r14.cvt32();
        case HostReg_x86_64.R15: return r15.cvt32();

        default: error_jit("Could not turn host register %s into a 32-bit xbyak register", host_reg); assert(0);
    }
}

Mmx to_xbyak_xmm(HostReg_x86_64 host_reg) {
    import std.format;

    switch (host_reg) {
        case HostReg_x86_64.XMM0: return xmm0;
        case HostReg_x86_64.XMM1: return xmm1;
        case HostReg_x86_64.XMM2: return xmm2;
        case HostReg_x86_64.XMM3: return xmm3;
        case HostReg_x86_64.XMM4: return xmm4;
        case HostReg_x86_64.XMM5: return xmm5;
        case HostReg_x86_64.XMM6: return xmm6;
        case HostReg_x86_64.XMM7: return xmm7;
        
        default: error_jit("Could not turn host register %s into an XMM register", host_reg); assert(0);
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
        
        default: error_jit("Could not turn host register %s into an 8-bit xbyak register", host_reg); assert(0);
    }
}