module emu.hw.broadway.jit.emission.helpers;

import util.number;

u32 generate_rlw_mask(u32 mb, u32 me) {
    // i hate this entire function

    int i = mb;
    int mask = 0;
    while (i != me) {
        mask |= (1 << (31 - i));
        i = (i + 1) & 0x1F;
    } 
    mask |= (1 << (31 - i));

    return mask;
}