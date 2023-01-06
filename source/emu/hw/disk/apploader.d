module emu.hw.disk.apploader;

import util.endian;
import util.number;

struct WiiApploader {
    u8[16] revision;
    u32_be entry_point;
    s32_be size;
    s32_be trailer_size;
    u8[4]  padding;
}

static assert (WiiApploader.sizeof == 32);

enum APPLOADER_LOAD_ADDRESS = 0x81200000;

