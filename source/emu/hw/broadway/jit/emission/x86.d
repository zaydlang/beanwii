module emu.hw.broadway.jit.emission.x86;

import gallinule.x86;
import std.algorithm;
import util.number;

u16 reg32_to_u16(R32 reg) {
    return cast(u16) [edi, esi, edx, ecx, r8d, r9d, eax, r10d, r11d, r12d, r13d, r14d, r15d].countUntil(reg);
}

R32 u16_to_reg32(u16 reg) {
    return [edi, esi, edx, ecx, r8d, r9d, eax, r10d, r11d, r12d, r13d, r14d, r15d][reg];
}