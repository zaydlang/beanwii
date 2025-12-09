import std.stdio;
import core.memory;

import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.readers.filereader;
import emu.hw.disk.readers.dol;
import emu.hw.disk.readers.wbfs;
import emu.hw.wii;
import ui.cli;
import ui.reng.device;
import ui.sdl.device;
import ui.runner;
import util.file;
import util.log;
import util.number;
import util.signal;

__gshared u32 g_fastmem_start_addr = 0x80000000;
__gshared u32 g_fastmem_end_addr = 0x80200000;

// TODO: i really hate this construct. how to make this cleaner?
__gshared Wii wii;
void logger_on_error_callback(){
	wii.on_error();
}

version (unittest) {} else {
	void main(string[] args) {
		CliArgs cli_args = parse_cli_args(args);

		if (!cli_args.start_debugger) {
		GC.disable();
	}
		
	wii = new Wii(cli_args.ringbuffer_size);
	
	if (cli_args.extension) {
		wii.get_wiimote().connect_extension(cli_args.extension.get());
	}

	auto device = new SdlDevice(wii, 1, cli_args.start_debugger, cli_args.record_audio, cli_args.use_bluetooth_wiimote);
		wii.init_opengl();	
		// auto device = new RengMultimediaDevice(wii, 1, true);

		auto disk_data = load_file_as_bytes(cli_args.rom_path);

		wii.connect_multimedia_device(device);

		set_logger_on_error_callback(&logger_on_error_callback);
		
		if (cli_args.install_segfault_handler) {
			set_segfault_callback(&logger_on_error_callback);
			install_segfault_handler();
		}

		parse_and_load_file(wii, disk_data);

		bool hang_in_gdb_at_start = cli_args.hang_in_gdb_at_start;
		if (hang_in_gdb_at_start) {
			wii.hang_in_gdb_at_start();
		}

		new Runner(wii, device).run();
	}
}
