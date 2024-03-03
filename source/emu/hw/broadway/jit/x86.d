module emu.hw.broadway.jit.x86;
import xbyak;

enum HostReg {
    RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI,
    R8,  R9,  R10, R11, R12, R13, R14, R15
}

public Reg64 to_xbyak_reg(HostReg host_reg) {
    final switch (host_reg) {
        case HostReg.RDI: return rdi;
        case HostReg.RSI: return rsi;
        case HostReg.RDX: return rdx;
        case HostReg.RCX: return rcx;
        case HostReg.R8: return r8;
        case HostReg.R9: return r9;
        case HostReg.RAX: return rax;
        case HostReg.RBX: return rbx;
        case HostReg.RBP: return rbp;
        case HostReg.R10: return r10;
        case HostReg.R11: return r11;
        case HostReg.R12: return r12;
        case HostReg.R13: return r13;
        case HostReg.R14: return r14;
        case HostReg.R15: return r15;
        case HostReg.RSP: return rsp;
    }
}

public bool is_caller_save(HostReg reg) {
    final switch (reg) {
        case HostReg.RAX:
        case HostReg.RCX:
        case HostReg.RDX:
        case HostReg.RSI:
        case HostReg.RDI:
        case HostReg.R8:
        case HostReg.R9:
        case HostReg.R10:
        case HostReg.R11:
            return true;
        case HostReg.RBX:
        case HostReg.RBP:
        case HostReg.R12:
        case HostReg.R13:
        case HostReg.R14:
        case HostReg.R15:
        case HostReg.RSP:
            return false;
    }
}

public bool is_callee_save(HostReg reg) {
    return !is_caller_save(reg);
}

// i need to unify HostReg and Reg64 sometime...
alias cpu_state_reg = rdi;
alias tmp_reg       = r15;
