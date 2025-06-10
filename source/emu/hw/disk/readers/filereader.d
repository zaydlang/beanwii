module emu.hw.disk.readers.filereader;

import emu.encryption.ticket;
import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.dol;
import emu.hw.disk.readers.wbfs;
import emu.hw.wii;
import util.log;
import util.number;

interface FileReader {
    public bool is_valid_file(u8[] file_data);
    public void load_file(Wii wii, u8[] file_data);
    public void decrypted_disk_read(size_t disk_slot, size_t address, void* out_buffer, size_t size);
	public void encrypted_disk_read(size_t disk_slot, size_t address, void* out_buffer, size_t size);
	public WiiTicket* get_ticket();
	public u32 get_tmd_size();
}

public void parse_and_load_file(Wii wii, u8[] file_data) {
	FileReader[] readers = [
		cast(FileReader) new WbfsReader(),
		cast(FileReader) new DolReader()
	];

	// readers is sorted in order of priority
	bool loaded = false;
	foreach (FileReader reader; readers) {
		if (reader.is_valid_file(file_data)) {
			reader.load_file(wii, file_data);
			loaded = true;
			break;
		}
	}

	if (!loaded) {
		error_wii("Unrecognized rom file format.");
	}
}