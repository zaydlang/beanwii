module emu.hw.disk.dol;

import util.endian;
import util.number;

struct WiiDol {
    u32_be[7]  text_offset;
    u32_be[11] data_offset;
    u32_be[7]  text_address;
    u32_be[11] data_address;
    u32_be[7]  text_size;
    u32_be[11] data_size;
    u32_be     bss_address;
    u32_be     bss_size;
    u32_be     entry_point;
    u8[28]     padding;
}

static assert(WiiDol.sizeof == 0x100);
