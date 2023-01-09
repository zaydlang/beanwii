module emu.hw.disk.readers.dol;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.diskreader;
import util.number;

import util.log;

final class DolReader : DiskReader {
    public bool is_valid_disk(u8* disk_data, size_t disk_size) {
        return true; // TODO
    }

    public void load_disk(u8* disk_data, size_t disk_size, WiiApploader** out_apploader, WiiDol** out_dol) {
        *out_dol = cast(WiiDol*) disk_data;
    }
}
