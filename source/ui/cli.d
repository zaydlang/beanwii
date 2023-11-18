module ui.cli;

import commandr;
import std.conv;

struct CliArgs {
    string rom_path;
    size_t ringbuffer_size;
    bool   start_debugger;
}

CliArgs parse_cli_args(string[] args) {
	auto program = new Program("BeanWii", "0.1").summary("Wii Emulator")
		.add(new Argument("rom_path", "path to rom file"))
        .add(new Option("r", "ringbuffer_size", "the number of instructions to capture in the broadway ring buffer")
            .optional().defaultValue("0"))
        .add(new Option("d", "debug", "start the debugger")
            .optional().defaultValue("false"))
        .parse(args);

    return CliArgs(
        program.arg("rom_path"),
        to!int(program.option("ringbuffer_size")),
        to!bool(program.option("debug"))
    );
}
