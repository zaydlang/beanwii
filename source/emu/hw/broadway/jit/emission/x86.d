module emu.hw.broadway.jit.emission.x86;

import std.algorithm;
import util.number;
import xbyak;

u16 reg64_to_u16(Reg64 reg) {
    return cast(u16) [rdi, rsi, rdx, rcx, r8, r9, rax, r10, r11, r12, r13, r14, r15].countUntil(reg);
}

Reg64 u16_to_reg64(u16 reg) {
    return [rdi, rsi, rdx, rcx, r8, r9, rax, r10, r11, r12, r13, r14, r15][reg];
}