module test.broadway.state.test;

import emu.hw.broadway.state;
import emu.hw.disk.readers.filereader;
import emu.hw.memory.strategy.slowmem.slowmem;
import emu.hw.wii;
import std.array;
import std.conv;
import std.file;
import std.range;
import std.stdio;
import test.nice_assert;
import util.file;
import util.number;

struct TestState {
    u32 pc;
    u32 lr;
    u32[32] gprs;
    u32[8] cr;
    u32 xer;
    u32 fpscr;
}

TestState get_golden_test_state(string line) {
    TestState state;
    auto parts = line.split(" ");
    state.pc = parts[3].parse!u32(16);

    for (int i = 0; i < 8; i++) {
        state.cr[i] = parts[9 + i].parse!u32(16);
    }

    state.xer = (parts[19].parse!u32(16)) << 29 | (parts[22].parse!u32(16)) << 30;
    state.fpscr = parts[24].parse!u32(16);
    state.lr = parts[28].parse!u32(16);

    for (int i = 0; i < 32; i++) {
        state.gprs[i] = parts[30 + i * 2].parse!u32(16);
    }

    return state;
}   

TestState get_actual_test_state(Wii wii) {
    TestState state;
    state.pc = wii.broadway.state.pc;

    for (int i = 0; i < 8; i++) {
        state.cr[i] = (wii.broadway.state.cr >> (4 * i)) & 0xF;
    }

    state.xer = wii.broadway.state.xer;
    state.fpscr = wii.broadway.state.fpscr;
    state.lr = wii.broadway.state.lr;
    
    for (int i = 0; i < 32; i++) {
        state.gprs[i] = wii.broadway.state.gprs[i];
    }

    return state;
}

enum tests = [
    "sanity",

    "addcx",
    "addex",
    "addic",
    "addic_rc",
    "addi",
    "addis",
    "addmex",
    "addx",
    "addzex",
    "andcx",
    "andi_rc",
    "andis_rc",
    "andx",
    "cmp",
    "cmpi",
    "cmpl",
    "cmpli",
    "cntlzwx",
    "divwux",
    "divwx",
    "eqvx",
    "extsbx",
    "extshx",
    "mulhwux",
    "mulhwx",
    "mulli",
    "mullwx",
    "nandx",
    "negx",
    "norx",
    "orcx",
    "ori",
    "oris",
    "orx",
    "rlwimix",
    "rlwinmx",
    "rlwnmx",
    "slwx",
    "srawix",
    "srawx",
    "srwx",
    "subfcx",
    "subfex",
    "subfic",
    "subfmex",
    "subfx",
    "subfzex",
    "tw",
    "twi",
    "xori",
    "xoris",
    "xorx",
];

static foreach (test; tests) {
    @(test)
    unittest {
        Wii wii = new Wii(0);

		auto disk_data = load_file_as_bytes("source/test/broadway/dols/" ~ test ~ ".dol");
		parse_and_load_file(wii, disk_data);

        auto golden_data = File("source/test/broadway/goldens/" ~ test ~ ".golden").byLine();
        golden_data.dropOne(); // Skip the header
        foreach (line; golden_data) {
            auto golden_state = get_golden_test_state(cast(string) line);
            auto actual_state = get_actual_test_state(wii);

            assert_eq(golden_state.pc, actual_state.pc);
            assert_eq(golden_state.lr, actual_state.lr);
            assert_eq(golden_state.xer, actual_state.xer);
            assert_eq(golden_state.fpscr, actual_state.fpscr);
            for (int j = 0; j < 8; j++) {
                assert_eq(golden_state.cr[j], actual_state.cr[j]);
            }

            for (int j = 0; j < 32; j++) {
                assert_eq(golden_state.gprs[j], actual_state.gprs[j]);
            }

            wii.single_step();
        }
    }
}