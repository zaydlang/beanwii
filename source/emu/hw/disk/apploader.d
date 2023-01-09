module emu.hw.disk.apploader;

import util.endian;
import util.number;

struct WiiApploader {
    align(1):

    WiiApploaderHeader header;
    u8[0] data;
}

struct WiiApploaderHeader {
    align(1):

    u8[16] revision;
    u32_be entry_point;
    s32_be size;
    s32_be trailer_size;
    u8[4]  padding;
}

static assert(WiiApploaderHeader.sizeof == 32);

enum WII_APPLOADER_LOAD_ADDRESS = 0x81200000;
