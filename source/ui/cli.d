module ui.cli;

import commandr;
import emu.hw.ipc.usb.extensions.extension;
import std.conv;
import std.typecons : Nullable;
import std.uni;
import util.log;
import util.number;

struct CliArgs {
    string rom_path;
    int    ringbuffer_size;
    bool   start_debugger;
    bool   hang_in_gdb_at_start;
    bool   record_audio;
    bool   install_segfault_handler;
    bool   use_bluetooth_wiimote;
    Nullable!WiimoteExtensionType extension;
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
        .add(new Option("e", "extension", "wiimote extension to attach (nunchuk)")
            .optional().defaultValue("none"))
        .add(new Flag("b", "bluetooth", "enable bluetooth wiimote support"))
        .parse(args);

    return CliArgs(
        program.arg("rom_path"),
        to!int(program.option("ringbuffer_size")),
        to!bool(program.flag("debug")),
        to!bool(program.flag("wait")),
        to!bool(program.flag("record")),
        to!bool(program.flag("install_segfault_handler")),
        to!bool(program.flag("bluetooth")),
        parse_extension(program.option("extension"))
    );
}

Nullable!WiimoteExtensionType parse_extension(string name) {
    auto lower = name.toLower();

    if (lower == "nunchuk" || lower == "nunchuck") {
        return Nullable!WiimoteExtensionType(WiimoteExtensionType.Nunchuk);
    }

    return Nullable!WiimoteExtensionType();
}
