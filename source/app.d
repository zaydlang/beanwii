import std.stdio;

import emu.hw.wii;
import util.file;

void main() {
	auto disk_data = load_file_as_bytes("./spm.wbfs");

	Wii wii = new Wii();
	wii.load_wii_disk(disk_data.ptr, disk_data.length);
	wii.run();
}
