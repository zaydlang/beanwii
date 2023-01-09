import std.stdio;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.diskreader;
import emu.hw.disk.readers.dol;
import emu.hw.disk.readers.wbfs;
import emu.hw.wii;
import util.file;
import util.log;

void main() {
	auto disk_data = load_file_as_bytes("./spm.wbfs");

	Wii wii = new Wii();

	WiiApploader* apploader = null;
	WiiDol* dol = null;

	bool loaded = false;
	foreach (DiskReader reader; [cast(DiskReader) new WbfsReader(), cast(DiskReader) new DolReader()]) {
		if (reader.is_valid_disk(disk_data.ptr, disk_data.length)) {
			reader.load_disk(disk_data.ptr, disk_data.length, &apploader, &dol);
			loaded = true;
		}
	}

	if (!loaded) {
		error_wii("Unrecognized rom file format.");
	}
	
	wii.load_wii_disk(apploader, dol);
	wii.run();
}
