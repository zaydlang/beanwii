module emu.hw.disk.dol;

import util.endian;
import util.number;

enum WII_DOL_NUM_TEXT_SECTIONS = 7;
enum WII_DOL_NUM_DATA_SECTIONS = 11;

struct WiiDol {
    u32_be[WII_DOL_NUM_TEXT_SECTIONS] text_offset;
    u32_be[WII_DOL_NUM_DATA_SECTIONS] data_offset;
    u32_be[WII_DOL_NUM_TEXT_SECTIONS] text_address;
    u32_be[WII_DOL_NUM_DATA_SECTIONS] data_address;
    u32_be[WII_DOL_NUM_TEXT_SECTIONS] text_size;
    u32_be[WII_DOL_NUM_DATA_SECTIONS] data_size;
    u32_be                            bss_address;
    u32_be                            bss_size;
    u32_be                            entry_point;
    u8[28]                            padding;
}

static assert(WiiDol.sizeof == 0x100);
