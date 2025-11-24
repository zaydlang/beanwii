module ui.cli;

import commandr;
import std.conv;
import util.number;

struct CliArgs {
    string rom_path;
    int    ringbuffer_size;
    bool   start_debugger;
    bool   hang_in_gdb_at_start;
    bool   record_audio;
    bool   install_segfault_handler;
    u32    fastmem_start_addr;
    u32    fastmem_end_addr;
}

CliArgs parse_cli_args(string[] args) {
	auto program = new Program("BeanWii", "0.1").summary("Wii Emulator")
		.add(new Argument("rom_path", "path to rom file"))
        .add(new Option("r", "ringbuffer_size", "the number of instructions to capture in the broadway ring buffer")
            .optional().defaultValue("0"))
        .add(new Flag("w", "wait", "immediately hang in gdb"))
        .add(new Flag("d", "debug", "start the debugger"))
        .add(new Flag("a", "record", "record audio samples to file"))
        .add(new Flag("i", "install_segfault_handler", "install segfault handler"))
        .add(new Option("b", "fastmem_start", "fastmem start address")
            .optional().defaultValue("80000000"))
        .add(new Option("c", "fastmem_end", "fastmem end address")
            .optional().defaultValue("80200000"))
        .parse(args);

    return CliArgs(
        program.arg("rom_path"),
        to!int(program.option("ringbuffer_size")),
        to!bool(program.flag("debug")),
        to!bool(program.flag("wait")),
        to!bool(program.flag("record")),
        to!bool(program.flag("install_segfault_handler")),
        to!u32(program.option("fastmem_start"), 16),
        to!u32(program.option("fastmem_end"), 16)
    );
}
