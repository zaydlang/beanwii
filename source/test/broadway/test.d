module test.broadway.state.test;

import consolecolors;
import emu.hw.broadway.state;
import emu.hw.disk.readers.filereader;
import emu.hw.memory.strategy.software_mem.software_mem;
import emu.hw.wii;
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format;
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
    u64[32] ps0;
    u64[32] ps1;
}

enum Diff {
    Unchanged           = 0,
    ChangedFromPrevious = 1,
    ChangedFromGolden   = 2,
    ChangedFromBoth     = 3,
}

struct DiffRepresentation {
    Diff pc;
    Diff lr;
    Diff[32] gprs;
    Diff[8] cr;
    Diff xer;
    Diff fpscr;
    Diff[32] ps0;
    Diff[32] ps1;
}

u32 instruction_for_golden_line(string line) {
    auto parts = line.split(" ");
    parts[1] = parts[1][2..$];
    return parts[1].parse!u32(16);
}

string disassembly_for_golden_line(string line, string test_name) {
    auto parts = line.split(" ");
    if (test_name.length > 0 && test_name[0] == 'f') {
        return parts[190..$].join(" ");
    } else {
        return parts[94..$].join(" ");
    }
}

bool is_failure(Diff diff) {
    return diff == Diff.ChangedFromGolden || diff == Diff.ChangedFromBoth;
}

bool is_failure(DiffRepresentation diff) {
    return is_failure(diff.pc) || is_failure(diff.lr) || is_failure(diff.xer) ||
        any!(a => is_failure(a))(diff.gprs[]) || any!(a => is_failure(a))(diff.cr[]) || 
        any!(a => is_failure(a))(diff.ps0[]) || any!(a => is_failure(a))(diff.ps1[]);
}

TestState get_golden_test_state(string line, string test_name) {
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

    if (test_name.length > 0 && test_name[0] == 'f') {
        for (int i = 0; i < 32; i++) {
            state.ps0[i] = parts[94 + i * 3].parse!u64(16);
            state.ps1[i] = parts[95 + i * 3].parse!u64(16);
        }
    }

    return state;
}   

TestState get_actual_test_state(Wii wii, string test_name) {
    TestState state;
    state.pc = wii.broadway.state.pc;

    for (int i = 0; i < 8; i++) {
        state.cr[7 - i] = (wii.broadway.state.cr >> (4 * i)) & 0xF;
    }

    state.xer = wii.broadway.state.xer;
    state.fpscr = wii.broadway.state.fpscr;
    state.lr = wii.broadway.state.lr;
    
    for (int i = 0; i < 32; i++) {
        state.gprs[i] = wii.broadway.state.gprs[i];
    }

    if (test_name.length > 0 && test_name[0] == 'f') {
        for (int i = 0; i < 32; i++) {
            state.ps0[i] = wii.broadway.state.ps[i].ps0;
            state.ps1[i] = wii.broadway.state.ps[i].ps1;
        }
    }

    return state;
}

DiffRepresentation get_diff(TestState previous, TestState golden, TestState actual) {
    DiffRepresentation diff;

    auto diff_helper = (u32 golden_value, u32 actual_value, u32 previous_value) {
        if (golden_value != actual_value && golden_value != previous_value) {
            return Diff.ChangedFromBoth;
        } else if (golden_value != previous_value) {
            return Diff.ChangedFromPrevious;
        } else if (golden_value != actual_value) {
            return Diff.ChangedFromGolden;
        } else {
            return Diff.Unchanged;
        } 
    };

    auto diff_helper_u64 = (u64 golden_value, u64 actual_value, u64 previous_value) {
        if (golden_value != actual_value && golden_value != previous_value) {
            return Diff.ChangedFromBoth;
        } else if (golden_value != previous_value) {
            return Diff.ChangedFromPrevious;
        } else if (golden_value != actual_value) {
            return Diff.ChangedFromGolden;
        } else {
            return Diff.Unchanged;
        } 
    };

    auto diff_helper_ps = (u64 golden_value, u64 actual_value, u64 previous_value) {
        import std.math : fabs;
        double golden_f = *cast(double*) &golden_value;
        double actual_f = *cast(double*) &actual_value;
        double previous_f = *cast(double*) &previous_value;
        double eps = 1e-3;
        
        bool golden_differs = fabs(golden_f - actual_f) > eps;
        bool previous_differs = fabs(golden_f - previous_f) > eps;
        
        if (golden_differs && previous_differs) {
            return Diff.ChangedFromBoth;
        } else if (previous_differs) {
            return Diff.ChangedFromPrevious;
        } else if (golden_differs) {
            return Diff.ChangedFromGolden;
        } else {
            return Diff.Unchanged;
        }
    };

    diff.pc = diff_helper(golden.pc, actual.pc, previous.pc);
    diff.lr = diff_helper(golden.lr, actual.lr, previous.lr);
    diff.xer = diff_helper(golden.xer, actual.xer, previous.xer);
    diff.fpscr = diff_helper(golden.fpscr, actual.fpscr, previous.fpscr);
    
    for (int i = 0; i < 32; i++) {
        diff.gprs[i] = diff_helper(golden.gprs[i], actual.gprs[i], previous.gprs[i]);
        diff.ps0[i] = diff_helper_ps(golden.ps0[i], actual.ps0[i], previous.ps0[i]);
        diff.ps1[i] = diff_helper_ps(golden.ps1[i], actual.ps1[i], previous.ps1[i]);
    }

    for (int i = 0; i < 8; i++) {
        diff.cr[i] = diff_helper(golden.cr[i], actual.cr[i], previous.cr[i]);
    }

    return diff;
}

string color_for_diff(Diff diff) {
    final switch (diff) {
        case Diff.ChangedFromPrevious: return "lcyan";
        case Diff.ChangedFromGolden: return "lred";
        case Diff.ChangedFromBoth: return "red";
        case Diff.Unchanged: return "";
    }
}

string colorize(string text, Diff diff) {
    return "<" ~ color_for_diff(diff) ~ ">" ~ text ~ "</" ~ color_for_diff(diff) ~ ">";
}

string to_hex_string(u32 value) {
    return "%08x".format(value);
}

void pretty_print_state(TestState state, DiffRepresentation diff, string test_name) {
    for (int i = 0; i < 32; i += 8) {
        cwritefln("\tGPRs %02d-%02d: %s %s %s %s %s %s %s %s",
            i, i + 7,
            colorize(state.gprs[i + 0].to_hex_string, diff.gprs[i + 0]),
            colorize(state.gprs[i + 1].to_hex_string, diff.gprs[i + 1]),
            colorize(state.gprs[i + 2].to_hex_string, diff.gprs[i + 2]),
            colorize(state.gprs[i + 3].to_hex_string, diff.gprs[i + 3]),
            colorize(state.gprs[i + 4].to_hex_string, diff.gprs[i + 4]),
            colorize(state.gprs[i + 5].to_hex_string, diff.gprs[i + 5]),
            colorize(state.gprs[i + 6].to_hex_string, diff.gprs[i + 6]),
            colorize(state.gprs[i + 7].to_hex_string, diff.gprs[i + 7]));
    }

    if (test_name.length > 0 && test_name[0] == 'f') {
        for (int i = 0; i < 32; i += 4) {
            cwritefln("\tPS  %02d-%02d: %s.%s %s.%s %s.%s %s.%s",
                i, i + 3,
                colorize("%016x".format(state.ps0[i + 0]), diff.ps0[i + 0]),
                colorize("%016x".format(state.ps1[i + 0]), diff.ps1[i + 0]),
                colorize("%016x".format(state.ps0[i + 1]), diff.ps0[i + 1]),
                colorize("%016x".format(state.ps1[i + 1]), diff.ps1[i + 1]),
                colorize("%016x".format(state.ps0[i + 2]), diff.ps0[i + 2]),
                colorize("%016x".format(state.ps1[i + 2]), diff.ps1[i + 2]),
                colorize("%016x".format(state.ps0[i + 3]), diff.ps0[i + 3]),
                colorize("%016x".format(state.ps1[i + 3]), diff.ps1[i + 3]));
        }
    }

    for (int i = 0; i < 8; i += 4) {
        cwritefln("\tCRs    %d-%d: %s %s %s %s",
            i, i + 3,
            colorize(state.cr[i + 0].to_hex_string, diff.cr[i + 0]),
            colorize(state.cr[i + 1].to_hex_string, diff.cr[i + 1]),
            colorize(state.cr[i + 2].to_hex_string, diff.cr[i + 2]),
            colorize(state.cr[i + 3].to_hex_string, diff.cr[i + 3]));
    }

    cwritefln("\t        PC: %s LR: %s XER: %s FPSCR: %s",
        colorize(state.pc.to_hex_string, diff.pc),
        colorize(state.lr.to_hex_string, diff.lr),
        colorize(state.xer.to_hex_string, diff.xer),
        colorize(state.fpscr.to_hex_string, diff.fpscr));

    // for (int i = 0; i < 32; i += 8) {
    //     cwritefln("\tGPRs %02d-%02d: %08x %08x %08x %08x %08x %08x %08x %08x",
    //         i, i + 7,
    //         state.gprs[i], state.gprs[i + 1], state.gprs[i + 2], state.gprs[i + 3],
    //         state.gprs[i + 4], state.gprs[i + 5], state.gprs[i + 6], state.gprs[i + 7]);
    // }

    // for (int i = 0; i < 8; i += 4) {
    //     cwritefln("\tCRs %d-%d: %08x %08x %08x %08x",
    //         i, i + 3,
    //         state.cr[i], state.cr[i + 1], state.cr[i + 2], state.cr[i + 3]);
    // }

    // cwritefln("\tPC: %08x LR: %08x XER: %08x FPSCR: %08x",
    //     state.pc, state.lr, state.xer, state.fpscr);
}

enum tests = [
    "sanity",

    // "addcx",
    // "addex",
    // "addic",
    // "addic_rc",
    // "addi",
    // "addis",
    // "addmex",
    // "addx",
    // "addzex",
    // "andcx",
    // "andi_rc",
    // "andis_rc",
    // "andx",
    // "cmp",
    // "cmpi",
    // "cmpl",
    // "cmpli",
    // "cntlzwx",
    // "divwux",
    // "divwx",
    // "eqvx",
    // "extsbx",
    // "extshx",
    // "mulhwux",
    // "mulhwx",
    // "mulli",
    // "mullwx",
    // "nandx",
    // "negx",
    // "norx",
    // "orcx",
    // "ori",
    // "oris",
    // "orx",
    // "rlwimix",
    // "rlwinmx",
    // "rlwnmx",
    // "slwx",
    // "srawix",
    // "srawx",
    // "srwx",
    // "subfcx",
    // "subfex",
    // "subfic",
    // "subfmex",
    // "subfx",
    // "subfzex",
    // "xori",
    // "xoris",
    // "xorx",

    "fabsx",
    "faddsx", 
    "faddx",
    "fcmpo",
    "fcmpu",
    "fctiwzx",
    "fctiwx",
    "fdivsx",
    "fdivx",
    "fmaddsx",
    "fmaddx",
    "fmrx",
    "fmsubsx",
    "fmsubx",
    "fmulsx",
    "fmulx",
    "fnabsx",
    "fnegx",
    "fnmaddsx",
    "fnmaddx",
    "fnmsubsx",
    "fnmsubx",
    "fresx",
    "frspx",
    "frsqrtex",
    "fselx",
    "fsubsx",
    "fsubx"
];

static foreach (test; tests) {
    @(test)
    unittest {
        Wii wii = new Wii(0);
        wii.broadway.enter_single_step_mode();

		auto disk_data = load_file_as_bytes("source/test/broadway/dols/" ~ test ~ ".dol");
		parse_and_load_file(wii, disk_data);

        auto golden_data = File("source/test/broadway/goldens/" ~ test ~ ".golden").byLine();
        golden_data.dropOne(); // Skip the header

        u32 previous_instruction = 0;
        string previous_disassembly = "";
        TestState previous_state = get_actual_test_state(wii, test);

        // pairwise iteration
        foreach (line; golden_data) {
            auto golden_state = get_golden_test_state(cast(string) line, test);
            auto actual_state = get_actual_test_state(wii, test);
            
            auto diff = get_diff(previous_state, golden_state, actual_state);
            
            if (is_failure(diff)) {
                writefln("===== Test %s Failed! =====", test);
                writefln("Instruction: %s (%08x)", previous_disassembly, previous_instruction);

                writefln("Previous state:");
                pretty_print_state(previous_state, diff, test);
                writefln("Expected:");
                pretty_print_state(golden_state, diff, test);
                writefln("Actual:");
                pretty_print_state(actual_state, diff, test);
                assert(0);
            }

            previous_state = actual_state;
            previous_instruction = instruction_for_golden_line(cast(string) line);
            previous_disassembly = disassembly_for_golden_line(cast(string) line, test);
            wii.single_step();
        }
    }
}