module ui.cli;

import commandr;
import std.conv;

struct CliArgs {
    string rom_path;
}

CliArgs parse_cli_args(string[] args) {
	auto program = new Program("BeanWii", "0.1").summary("Wii Emulator")
		.add(new Argument("rom_path", "path to rom file"))
        .parse(args);

    return CliArgs(
        program.arg("rom_path"),
    );
}
