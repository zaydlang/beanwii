import std.stdio;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.diskreader;
import emu.hw.disk.readers.dol;
import emu.hw.disk.readers.wbfs;
import emu.hw.wii;
import ui.cli;
import ui.reng.device;
import ui.runner;
import util.file;
import util.log;

void main(string[] args) {
	CliArgs cli_args = parse_cli_args(args);

	auto disk_data = load_file_as_bytes(cli_args.rom_path);

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
	
	auto reng = new RengMultimediaDevice(1, false);
	wii.connect_multimedia_device(reng);
	
	wii.load_wii_disk(apploader, dol);
	new Runner(wii, reng).run();
}
