module source.test.broadway.test_paired_single;

import core.stdc.math;
import emu.hw.broadway.cpu;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.wii;
import emu.scheduler;
import std.stdio;
import util.force_cast;
import util.number;

class PairedSingleTester {
    private Wii wii;
    private Broadway broadway;
    private Mem mem;
    
    private enum u32 TEST_INSTRUCTION_ADDR = 0x80003000;
    private enum u32 TEST_DATA_ADDR = 0x80004000;
    private enum u32 TEST_STACK_ADDR = 0x80005000;

    this() {
        wii = new Wii(1000);
        broadway = wii.broadway;
        mem = wii.mem;
        
        broadway.reset();
        broadway.set_gpr(1, TEST_STACK_ADDR);
        broadway.enter_single_step_mode();
    }

    u32 encode_psq_l(int frD, int rA, int W, int I, int d) {
        return 0xE0000000 | (frD << 21) | (rA << 16) | (W << 15) | (I << 12) | (d & 0xFFF);
    }

    u32 encode_psq_st(int frS, int rA, int W, int I, int d) {
        return 0xF0000000 | (frS << 21) | (rA << 16) | (W << 15) | (I << 12) | (d & 0xFFF);
    }

    u32 encode_ps_abs(int frD, int frB, bool rc = false) {
        return 0x10000210 | (frD << 21) | (frB << 11) | (rc ? 1 : 0);
    }

    void setup_gqr(int index, int load_type, int load_scale, int store_type, int store_scale) {
        u32 gqr_value = (load_type << 16) | (load_scale << 24) | (store_type << 0) | (store_scale << 8);
        broadway.state.gqrs[index] = gqr_value;
        writefln("GQR%d set to 0x%08x (load_type=%d, load_scale=%d, store_type=%d, store_scale=%d)", 
            index, gqr_value, load_type, load_scale, store_type, store_scale);
    }

    void write_test_data(u32 address, u8[] data) {
        for (int i = 0; i < data.length; i++) {
            mem.cpu_write_u8(address + i, data[i]);
        }
    }

    void verify_ps_register(int reg, double expected_ps0, double expected_ps1, string test_name) {
        double actual_ps0 = force_cast!double(broadway.state.ps[reg].ps0);
        double actual_ps1 = force_cast!double(broadway.state.ps[reg].ps1);
        
        writefln("%x %x", broadway.state.ps[reg].ps0, broadway.state.ps[reg].ps1);
        double eps = 1e-6;
        if (fabs(actual_ps0 - expected_ps0) > eps || fabs(actual_ps1 - expected_ps1) > eps) {
            writefln("FAIL %s: f%d expected (%.6f, %.6f), got (%.6f, %.6f)", 
                test_name, reg, expected_ps0, expected_ps1, actual_ps0, actual_ps1);
            assert(false);
        } else {
            writefln("PASS %s: f%d = (%.6f, %.6f)", test_name, reg, actual_ps0, actual_ps1);
        }
    }

    void verify_memory_contents(u32 address, u8[] expected, string test_name) {
        for (int i = 0; i < expected.length; i++) {
            u8 actual = mem.cpu_read_u8(address + i);
            if (actual != expected[i]) {
                writefln("FAIL %s: memory[0x%08x+%d] expected 0x%02x, got 0x%02x", 
                    test_name, address, i, expected[i], actual);
                assert(false);
            }
        }
        writefln("PASS %s: memory contents match", test_name);
    }

    void execute_instruction(u32 instruction) {
        broadway.set_pc(TEST_INSTRUCTION_ADDR);
        mem.cpu_write_u32(TEST_INSTRUCTION_ADDR, instruction);
        broadway.single_step();
    }

    void test_psq_l_basic_w0() {
        writeln("=== Test 1: psq_l basic with W=0 ===");
        
        u8[] test_data = [0x3F, 0x80, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00];
        write_test_data(TEST_DATA_ADDR, test_data);
        
        setup_gqr(0, 0, 0, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_l(1, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        verify_ps_register(1, 1.0, 2.0, "psq_l basic W=0");
    }

    void test_psq_l_basic_w1() {
        writeln("=== Test 2: psq_l basic with W=1 ===");
        
        u8[] test_data = [0x3F, 0x80, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00];
        write_test_data(TEST_DATA_ADDR, test_data);
        
        setup_gqr(0, 0, 0, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_l(1, 3, 1, 0, 0);
        execute_instruction(instruction);
        
        verify_ps_register(1, 1.0, 1.0, "psq_l basic W=1");
    }

    void test_psq_l_quantized_u8() {
        writeln("=== Test 3: psq_l with u8 quantization ===");
        
        u8[] test_data = [0x80, 0xFF, 0x00, 0x40];
        write_test_data(TEST_DATA_ADDR, test_data);
        
        setup_gqr(0, 4, 8, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_l(2, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        double expected_ps0 = 128.0 / 256.0;
        double expected_ps1 = 255.0 / 256.0;
        verify_ps_register(2, expected_ps0, expected_ps1, "psq_l u8 quantization");
    }

    void test_psq_l_quantized_u16() {
        writeln("=== Test 4: psq_l with u16 quantization ===");
        
        u8[] test_data = [0x80, 0x00, 0xFF, 0xFF];
        write_test_data(TEST_DATA_ADDR, test_data);
        
        setup_gqr(0, 5, 16, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_l(3, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        double expected_ps0 = 32768.0 / 65536.0;
        double expected_ps1 = 65535.0 / 65536.0;
        verify_ps_register(3, expected_ps0, expected_ps1, "psq_l u16 quantization");
    }

    void test_psq_l_quantized_s8() {
        writeln("=== Test 5: psq_l with s8 quantization ===");
        
        u8[] test_data = [0x80, 0x7F, 0xFF, 0x00];
        write_test_data(TEST_DATA_ADDR, test_data);
        
        setup_gqr(0, 6, 7, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_l(2, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        double expected_ps0 = -128.0 / 128.0;
        double expected_ps1 = 127.0 / 128.0;
        verify_ps_register(2, expected_ps0, expected_ps1, "psq_l s8 quantization");
    }

    void test_psq_l_quantized_s16() {
        writeln("=== Test 6: psq_l with s16 quantization ===");
        
        u8[] test_data = [0x80, 0x00, 0x7F, 0xFF];
        write_test_data(TEST_DATA_ADDR, test_data);
        
        setup_gqr(0, 7, 15, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_l(3, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        double expected_ps0 = -32768.0 / 32768.0;
        double expected_ps1 = 32767.0 / 32768.0;
        verify_ps_register(3, expected_ps0, expected_ps1, "psq_l s16 quantization");
    }

    void test_psq_st_basic_w0() {
        writeln("=== Test 6: psq_st basic with W=0 ===");
        
        broadway.state.ps[5].ps0 = force_cast!u64(1.5);
        broadway.state.ps[5].ps1 = force_cast!u64(2.25);
        
        setup_gqr(0, 0, 0, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(5, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x3F, 0xC0, 0x00, 0x00, 0x40, 0x10, 0x00, 0x00];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st basic W=0");
    }

    void test_psq_st_basic_w1() {
        writeln("=== Test 7: psq_st basic with W=1 ===");
        
        broadway.state.ps[6].ps0 = force_cast!u64(1.5);
        broadway.state.ps[6].ps1 = force_cast!u64(2.25);
        
        setup_gqr(0, 0, 0, 0, 0);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        for (int i = 0; i < 8; i++) {
            mem.cpu_write_u8(TEST_DATA_ADDR + i, 0x00);
        }
        
        u32 instruction = encode_psq_st(6, 3, 1, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x3F, 0xC0, 0x00, 0x00];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st basic W=1");
    }

    void test_psq_st_quantized_u8() {
        writeln("=== Test 8: psq_st with u8 quantization ===");
        
        broadway.state.ps[7].ps0 = force_cast!u64(0.5);
        broadway.state.ps[7].ps1 = force_cast!u64(1.0);
        
        setup_gqr(0, 0, 0, 4, 8);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(7, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x80, 0xFF];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st u8 quantization");
    }

    void test_psq_st_quantized_u16() {
        writeln("=== Test 9: psq_st with u16 quantization ===");
        
        broadway.state.ps[8].ps0 = force_cast!u64(0.5);
        broadway.state.ps[8].ps1 = force_cast!u64(1.0);
        
        setup_gqr(0, 0, 0, 5, 16);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(8, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x80, 0x00, 0xFF, 0xFF];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st u16 quantization");
    }

    void test_psq_st_quantized_s8() {
        writeln("=== Test 10: psq_st with s8 quantization ===");
        
        broadway.state.ps[9].ps0 = force_cast!u64(-1.0);
        broadway.state.ps[9].ps1 = force_cast!u64(0.5);
        
        setup_gqr(0, 0, 0, 6, 7);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(9, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x80, 0x40];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st s8 quantization");
    }

    void test_psq_st_quantized_s16() {
        writeln("=== Test 11: psq_st with s16 quantization ===");
        
        broadway.state.ps[10].ps0 = force_cast!u64(-1.0);
        broadway.state.ps[10].ps1 = force_cast!u64(0.5);
        
        setup_gqr(0, 0, 0, 7, 15);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(10, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x80, 0x00, 0x40, 0x00];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st s16 quantization");
    }

    void test_psq_st_clamping_u8() {
        writeln("=== Test 12: psq_st u8 clamping ===");
        
        broadway.state.ps[11].ps0 = force_cast!u64(2.0);
        broadway.state.ps[11].ps1 = force_cast!u64(-1.0);
        
        setup_gqr(0, 0, 0, 4, 8);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(11, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0xFF, 0x00];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st u8 clamping");
    }

    void test_psq_st_clamping_u16() {
        writeln("=== Test 13: psq_st u16 clamping ===");
        
        broadway.state.ps[12].ps0 = force_cast!u64(2.0);
        broadway.state.ps[12].ps1 = force_cast!u64(-1.0);
        
        setup_gqr(0, 0, 0, 5, 16);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(12, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0xFF, 0xFF, 0x00, 0x00];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st u16 clamping");
    }

    void test_psq_st_clamping_s8() {
        writeln("=== Test 14: psq_st s8 clamping ===");
        
        broadway.state.ps[13].ps0 = force_cast!u64(2.0);
        broadway.state.ps[13].ps1 = force_cast!u64(-2.0);
        
        setup_gqr(0, 0, 0, 6, 7);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(13, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x7F, 0x80];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st s8 clamping");
    }

    void test_psq_st_clamping_s16() {
        writeln("=== Test 15: psq_st s16 clamping ===");
        
        broadway.state.ps[14].ps0 = force_cast!u64(2.0);
        broadway.state.ps[14].ps1 = force_cast!u64(-2.0);
        
        setup_gqr(0, 0, 0, 7, 15);
        
        broadway.set_gpr(3, TEST_DATA_ADDR);
        
        u32 instruction = encode_psq_st(14, 3, 0, 0, 0);
        execute_instruction(instruction);
        
        u8[] expected = [0x7F, 0xFF, 0x80, 0x00];
        verify_memory_contents(TEST_DATA_ADDR, expected, "psq_st s16 clamping");
    }

    void test_ps_abs_positive() {
        writeln("=== Test 16: ps_abs with positive values ===");
        
        broadway.state.ps[15].ps0 = force_cast!u64(1.5);
        broadway.state.ps[15].ps1 = force_cast!u64(2.25);
        
        u32 instruction = encode_ps_abs(16, 15);
        execute_instruction(instruction);
        
        verify_ps_register(16, 1.5, 2.25, "ps_abs positive values");
    }

    void test_ps_abs_negative() {
        writeln("=== Test 17: ps_abs with negative values ===");
        
        broadway.state.ps[17].ps0 = force_cast!u64(-1.5);
        broadway.state.ps[17].ps1 = force_cast!u64(-2.25);
        
        u32 instruction = encode_ps_abs(18, 17);
        execute_instruction(instruction);
        
        verify_ps_register(18, 1.5, 2.25, "ps_abs negative values");
    }

    void test_ps_abs_mixed() {
        writeln("=== Test 18: ps_abs with mixed values ===");
        
        broadway.state.ps[19].ps0 = force_cast!u64(-3.14);
        broadway.state.ps[19].ps1 = force_cast!u64(2.71);
        
        u32 instruction = encode_ps_abs(20, 19);
        execute_instruction(instruction);
        
        verify_ps_register(20, 3.14, 2.71, "ps_abs mixed values");
    }

}

@("psq_l basic with W=0")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_l_basic_w0();
}

@("psq_l basic with W=1")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_l_basic_w1();
}

@("psq_l with u8 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_l_quantized_u8();
}

@("psq_l with u16 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_l_quantized_u16();
}

@("psq_l with s8 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_l_quantized_s8();
}

@("psq_l with s16 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_l_quantized_s16();
}

@("psq_st basic with W=0")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_basic_w0();
}

@("psq_st basic with W=1")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_basic_w1();
}

@("psq_st with u8 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_quantized_u8();
}

@("psq_st with u16 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_quantized_u16();
}

@("psq_st with s8 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_quantized_s8();
}

@("psq_st with s16 quantization")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_quantized_s16();
}

@("psq_st u8 clamping")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_clamping_u8();
}

@("psq_st u16 clamping")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_clamping_u16();
}

@("psq_st s8 clamping")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_clamping_s8();
}

@("psq_st s16 clamping")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_psq_st_clamping_s16();
}

@("ps_abs positive values")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_ps_abs_positive();
}

@("ps_abs negative values")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_ps_abs_negative();
}

@("ps_abs mixed values")
unittest {
    auto tester = new PairedSingleTester();
    tester.test_ps_abs_mixed();
}