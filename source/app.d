import std.stdio;

import emu.hw.disk.diskloader;
import util.file;

void main() {
	auto disk_data = load_file_as_bytes("./spm.wbfs");
	load_wii_disk(disk_data.ptr, disk_data.length);
}
