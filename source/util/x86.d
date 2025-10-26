module util.x86;

import gallinule.x86;
import std.algorithm;
import util.number;

u16 reg32_to_u16(R32 reg) {
    return cast(u16) [edi, esi, edx, ecx, r8d, r9d, eax, r10d, r11d, r12d, r13d, r14d, r15d].countUntil(reg);
}

R32 u16_to_reg32(u16 reg) {
    return [edi, esi, edx, ecx, r8d, r9d, eax, r10d, r11d, r12d, r13d, r14d, r15d][reg];
}

u16 reg64_to_u16(R64 reg) {
    return cast(u16) [rdi, rsi, rdx, rcx, r8, r9, rax, r10, r11, r12, r13, r14, r15].countUntil(reg);
}

R64 u16_to_reg64(u16 reg) {
    return [rdi, rsi, rdx, rcx, r8, r9, rax, r10, r11, r12, r13, r14, r15][reg];
}