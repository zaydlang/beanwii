import std.stdio;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.filereader;
import emu.hw.disk.readers.dol;
import emu.hw.disk.readers.wbfs;
import emu.hw.wii;
import ui.cli;
import ui.reng.device;
import ui.runner;
import util.file;
import util.log;


// TODO: i really hate this construct. how to make this cleaner?
__gshared Wii wii;
void logger_on_error_callback(){
	wii.on_error();
}

version (unittest) {} else {
	void main(string[] args) {
		CliArgs cli_args = parse_cli_args(args);

		auto disk_data = load_file_as_bytes(cli_args.rom_path);

		wii = new Wii(cli_args.ringbuffer_size);
		
		set_logger_on_error_callback(&logger_on_error_callback);

		parse_and_load_file(wii, disk_data);
		
		auto reng = new RengMultimediaDevice(1, false);
		wii.connect_multimedia_device(reng);
		
		new Runner(wii, reng).run();
	}
}