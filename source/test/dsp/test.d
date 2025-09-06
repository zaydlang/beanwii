module test.dsp.test;

import consolecolors;
import emu.hw.dsp.dsp;
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

struct DspTestState {
    u16[31] reg;
}

enum Diff {
    Unchanged           = 0,
    ChangedFromPrevious = 1,
    ChangedFromGolden   = 2,
    ChangedFromBoth     = 3,
}

struct DspDiffRepresentation {
    Diff[31] reg;
}

bool is_failure(Diff diff) {
    return diff == Diff.ChangedFromGolden || diff == Diff.ChangedFromBoth;
}

bool is_failure(DspDiffRepresentation diff) {
    return any!(a => is_failure(a))(diff.reg[]);
}

struct DspTestCase {
    u16[] instructions;
    DspTestState initial_state;
    DspTestState expected_state;
}

struct DspTestFile {
    u16 instruction_length;
    DspTestCase[] test_cases;
}

DspTestFile parse_test_file(string filepath) {
    DspTestFile test_file;
    
    auto file_data = load_file_as_bytes(filepath);
    size_t offset = 0;
    
    test_file.instruction_length = (cast(u16[]) file_data[offset..offset + 2])[0];
    offset += 2;
    
    while (offset + test_file.instruction_length + (31 * 2 * 2) <= file_data.length) {
        DspTestCase test_case;
        
        test_case.instructions = cast(u16[]) file_data[offset..offset + test_file.instruction_length];
        offset += test_file.instruction_length;
        
        for (int i = 0; i < 31; i++) {
            test_case.expected_state.reg[i] = (cast(u16[]) file_data[offset..offset + 2])[0];
            offset += 2;
        }
        
        for (int i = 0; i < 31; i++) {
            test_case.initial_state.reg[i] = (cast(u16[]) file_data[offset..offset + 2])[0];
            offset += 2;
        }
        
        test_file.test_cases ~= test_case;
    }
    
    return test_file;
}

DspTestState get_actual_dsp_state(DSP dsp) {
    DspTestState state;
    
    for (int i = 0; i < 31; i++) {
        int dsp_reg_index = (i < 18) ? i : i + 1;
        state.reg[i] = dsp.dsp_state.get_reg(dsp_reg_index);
    }
    
    return state;
}

void set_dsp_state(DSP dsp, DspTestState state) {
    for (int i = 0; i < 31; i++) {
        int dsp_reg_index = (i < 18) ? i : i + 1;
        dsp.dsp_state.set_reg(dsp_reg_index, state.reg[i]);
    }
}

DspDiffRepresentation get_dsp_diff(DspTestState previous, DspTestState golden, DspTestState actual) {
    DspDiffRepresentation diff;

    auto diff_helper = (u16 golden_value, u16 actual_value, u16 previous_value) {
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

    for (int i = 0; i < 31; i++) {
        diff.reg[i] = diff_helper(golden.reg[i], actual.reg[i], previous.reg[i]);
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

string to_hex_string(u16 value) {
    return "%04x".format(value);
}

void pretty_print_dsp_state(DspTestState state, DspDiffRepresentation diff) {
    for (int i = 0; i < 32; i += 8) {
        int end_i = (i + 7 < 32) ? i + 7 : 31;
        cwrite("\tRegs x%02d-x%02d: ".format(i, end_i));
        
        for (int j = i; j <= end_i && j < 32; j++) {
            if (j == 18) {
                cwrite("----");
            } else {
                int reg_index = (j < 18) ? j : j - 1;
                cwrite(colorize(state.reg[reg_index].to_hex_string, diff.reg[reg_index]));
            }
            if (j < end_i && j < 31) cwrite(" ");
        }
        cwriteln("");
    }
    
    // Display long accumulators (AC0 and AC1)
    cwrite("\tAC0: ");
    cwrite(colorize(state.reg[16].to_hex_string, diff.reg[16]));
    cwrite(":");
    cwrite(colorize(state.reg[29].to_hex_string, diff.reg[29]));
    cwrite(":");
    cwrite(colorize(state.reg[27].to_hex_string, diff.reg[27]));
    cwrite("  AC1: ");
    cwrite(colorize(state.reg[17].to_hex_string, diff.reg[17]));
    cwrite(":");
    cwrite(colorize(state.reg[30].to_hex_string, diff.reg[30])); 
    cwrite(":");
    cwrite(colorize(state.reg[28].to_hex_string, diff.reg[28]));
    cwriteln("");
    
    // Display short accumulators (AX0 and AX1)
    cwrite("\tAX0: ");
    cwrite(colorize(state.reg[25].to_hex_string, diff.reg[25])); // AX0 hi
    cwrite(":");
    cwrite(colorize(state.reg[23].to_hex_string, diff.reg[23])); // AX0 lo
    cwrite("  AX1: ");
    cwrite(colorize(state.reg[26].to_hex_string, diff.reg[26])); // AX1 hi
    cwrite(":");
    cwrite(colorize(state.reg[24].to_hex_string, diff.reg[24])); // AX1 lo
    cwriteln("");
}

string format_instructions(u16[] instructions) {
    string result = "";
    for (int i = 0; i < instructions.length; i++) {
        result ~= "%04x".format(instructions[i]);
        if (i < instructions.length - 1) result ~= " ";
    }
    return result;
}

void run_dsp_test(string test_name) {
    DspTestFile test_file = parse_test_file("source/test/dsp/tests/" ~ test_name ~ ".bin");
    DSP dsp = new DSP();
    
    for (size_t test_case_idx = 0; test_case_idx < test_file.test_cases.length; test_case_idx++) {
        auto test_case = test_file.test_cases[test_case_idx];
        
        set_dsp_state(dsp, test_case.initial_state);
        DspTestState previous_state = test_case.initial_state;

        // upload instructions + halt 
        dsp.jit.upload_iram(test_case.instructions ~ [cast(ushort) 0x0021]);
        dsp.dsp_state.pc = 0;
        dsp.jit.single_step_until_halt(&dsp.dsp_state);
        
        DspTestState actual_state = get_actual_dsp_state(dsp);
        auto diff = get_dsp_diff(previous_state, test_case.expected_state, actual_state);
        
        if (is_failure(diff)) {
            writefln("===== DSP Test %s Failed! =====", test_name);
            writefln("Test case: %d", test_case_idx);
            writefln("Instructions: %s", format_instructions(test_case.instructions));

            writefln("Initial state:");
            pretty_print_dsp_state(test_case.initial_state, diff);
            writefln("Expected:");
            pretty_print_dsp_state(test_case.expected_state, diff);
            writefln("Actual:");
            pretty_print_dsp_state(actual_state, diff);
            assert(0);
        }
    }
}

enum dsp_tests = [
    "sanity",
    "abs",
    "add",
    "addarn"
];

static foreach (test; dsp_tests) {
    @("dsp_" ~ test)
    unittest {
        run_dsp_test(test);
    }
}