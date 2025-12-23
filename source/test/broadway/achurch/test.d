module test.broadway.achurch.test;

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
import std.path;
import std.range;
import std.stdio;
import test.broadway.achurch.pretty_printer;
import test.nice_assert;
import util.file;
import util.number;

@("achurch")
unittest {
    cwriteln("\n<lgreen>=== Running Achurch PowerPC Test Suite ===</lgreen>");
    
    Wii wii = new Wii(0);
    
    string test_dir = dirName(__FILE__);
    string achurch_binary = buildPath(test_dir, "achurch.raw");
    
    if (!exists(achurch_binary)) {
        cwritefln("<lred>Error: Achurch binary not found at %s</lred>", achurch_binary);
        assert(false, "Achurch binary missing");
    }
    
    auto binary_data = load_file_as_bytes(achurch_binary);
    
    const u32 load_addr = 0x0100_0000;
    for (size_t i = 0; i < binary_data.length; i++) {
        wii.mem.physical_write_u8(load_addr + cast(u32)i, binary_data[i]);
    }
    
    wii.broadway.state.pc = load_addr;
    
    cwritefln("<lcyan>Loaded achurch binary: %s (%d bytes)</lcyan>", achurch_binary, binary_data.length);
    
    const u32 SCRATCH_BUFFER_SIZE = 1024 * 1024;
    const u32 FAILURE_BUFFER_SIZE = 32 * 1024;
    
    const u32 scratch_addr = 0x0010_0000;
    const u32 failure_addr = 0x0020_0000;
    
    for (u32 i = 0; i < SCRATCH_BUFFER_SIZE; i += 4) {
        wii.mem.physical_write_u32(scratch_addr + i, 0);
    }
    for (u32 i = 0; i < FAILURE_BUFFER_SIZE; i += 4) {
        wii.mem.physical_write_u32(failure_addr + i, 0);
    }
    
    wii.broadway.state.gprs[3] = 0;
    wii.broadway.state.gprs[4] = scratch_addr;
    wii.broadway.state.gprs[5] = failure_addr;
    
    wii.broadway.state.ps[1].ps0 = 0x3FF00000;
    wii.broadway.state.ps[1].ps1 = 0x00000000;
    wii.broadway.state.gprs[6] = 0x3FF00000;
    wii.broadway.state.gprs[7] = 0x00000000;

    wii.broadway.state.msr &= ~(0b11 << 4);
    
    cwriteln("<lcyan>Test parameters set up:</lcyan>");
    cwritefln("  R3 (zero): 0x%08X", wii.broadway.state.gprs[3]);
    cwritefln("  R4 (scratch): 0x%08X", wii.broadway.state.gprs[4]);
    cwritefln("  R5 (failures): 0x%08X", wii.broadway.state.gprs[5]);
    cwritefln("  R6/R7 (1.0): 0x%08X%08X", wii.broadway.state.gprs[6], wii.broadway.state.gprs[7]);
    
    cwriteln("\n<lyellow>Executing achurch test suite...</lyellow>");
    
    u32 initial_pc = wii.broadway.state.pc;
    u32 execution_cycles = 0;
    const u32 MAX_CYCLES = 10_000_000;
    
    while (execution_cycles < MAX_CYCLES) {
        if (execution_cycles > 1000 && wii.broadway.state.pc == initial_pc) {
            break;
        }
        
        u32 current_instruction = wii.mem.physical_read_u32(wii.broadway.state.pc);
        if ((current_instruction & 0xFFFFFFFF) == 0x4E800020) {
            u32 lr_target = wii.broadway.state.lr;
            if (lr_target == initial_pc || lr_target == 0) {
                wii.single_step();
                break;
            }
        }
        
        wii.single_step();
        execution_cycles++;
        
        if (execution_cycles % 100000 == 0) {
            cwritefln("<lblue>Execution progress: %d cycles, PC: 0x%08X</lblue>", execution_cycles, wii.broadway.state.pc);
        }
    }
    
    if (execution_cycles >= MAX_CYCLES) {
        cwriteln("<lred>Warning: Test execution hit cycle limit, may not have completed</lred>");
    }
    
    u32 failure_count = wii.broadway.state.gprs[3];
    
    cwritefln("\n<lcyan>Test execution completed after %d cycles</lcyan>", execution_cycles);
    cwritefln("<lcyan>Final PC: 0x%08X</lcyan>", wii.broadway.state.pc);
    
    if (cast(int)failure_count < 0) {
        cwritefln("<lred>Bootstrap failure! Return code: %d</lred>", cast(int)failure_count);
        assert(false, "Achurch test failed to bootstrap");
    }
    
    cwritefln("<lcyan>Failure count: %u</lcyan>", failure_count);
    
    if (failure_count == 0) {
        cwriteln("\n<lgreen>🎉 All Achurch tests passed! 🎉</lgreen>");
        return;
    }
    
    FailureRecord[] failure_records;
    failure_records.length = failure_count;
    
    for (u32 i = 0; i < failure_count; i++) {
        u32 record_addr = failure_addr + (i * 32);
        FailureRecord record;
        
        record.instruction_word = wii.mem.physical_read_u32(record_addr + 0);
        record.instruction_address = wii.mem.physical_read_u32(record_addr + 4);
        record.aux_data0 = wii.mem.physical_read_u32(record_addr + 8);
        record.aux_data1 = wii.mem.physical_read_u32(record_addr + 12);
        record.aux_data2 = wii.mem.physical_read_u32(record_addr + 16);
        record.aux_data3 = wii.mem.physical_read_u32(record_addr + 20);
        record.unused0 = wii.mem.physical_read_u32(record_addr + 24);
        record.unused1 = wii.mem.physical_read_u32(record_addr + 28);
        
        failure_records[i] = record;
    }
    
    cwriteln();
    print_achurch_failures(failure_count, failure_records);
    
    assert(false, format("Achurch test suite failed with %u failures", failure_count));
}