module emu.hw.disk.readers.diskreader;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;

import util.number;

interface DiskReader {
    public bool is_valid_disk(u8* disk_data, size_t disk_size);
    public void load_disk(u8* disk_data, size_t disk_size, WiiApploader** out_apploader, WiiDol** out_dol);
}
