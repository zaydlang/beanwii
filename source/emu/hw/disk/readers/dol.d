module emu.hw.disk.readers.dol;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.filereader;
import emu.hw.wii;
import util.number;
import util.log;

final class DolReader : FileReader {
    private bool is_valid_section(u32 section_offset, u32 section_address, u32 section_size, u8[] file_data) {
        if (section_size != 0) {
            if (section_offset > file_data.length) return false;
            if (section_offset + section_size > file_data.length) return false;
            if (section_address >> 28 != 0x8) return false;
        }

        return true;
    }

    override public bool is_valid_file(u8[] file_data) {
        if (file_data.length < WiiDolHeader.sizeof) {
            return false;
        }

        WiiDolHeader* dol_header = cast(WiiDolHeader*) file_data.ptr;
        
        for (int i = 0; i < WII_DOL_NUM_TEXT_SECTIONS; i++) {
            u32 section_offset  = cast(u32) dol_header.text_offset[i];
            u32 section_address = cast(u32) dol_header.text_address[i];
            u32 section_size    = cast(u32) dol_header.text_size[i];
            if (!is_valid_section(section_offset, section_address, section_size, file_data)) return false;
        }

        for (int i = 0; i < WII_DOL_NUM_DATA_SECTIONS; i++) {
            u32 section_offset  = cast(u32) dol_header.data_offset[i];
            u32 section_address = cast(u32) dol_header.data_address[i];
            u32 section_size    = cast(u32) dol_header.data_size[i];
            if (!is_valid_section(section_offset, section_address, section_size, file_data)) return false;
        }

        if (cast(u32) dol_header.bss_size != 0) {
            if (cast(u32) dol_header.bss_address >> 28 != 0x8) return false;
        }

        return true;
    }

    override public void load_file(Wii wii, u8[] file_data) {
        assert(is_valid_file(file_data));

        wii.load_dol(cast(WiiDol*) file_data.ptr);
    }
}
