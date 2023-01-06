module emu.hw.disk.dol;

import util.endian;
import util.number;

enum WII_DOL_NUM_TEXT_SECTIONS = 7;
enum WII_DOL_NUM_DATA_SECTIONS = 11;

struct WiiDolHeader {
    align(1):

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

static assert(WiiDolHeader.sizeof == 0x100);

struct WiiDol {
    align(1):

    WiiDolHeader header;
    u8[] data;
}
