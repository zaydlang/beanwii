module emu.hw.dsp.jit.memory;

import util.bitop;
import util.number;
import util.log;

final class DspMemory {
    u16[0x10000] instruction_memory;
    u16[0x1800] data_memory;

    this() {

    }

    u16 read_instruction(u16 address) {
        if (address <= 0x0FFF) {
            return instruction_memory[address];
        } else if (address >= 0x8000 && address <= 0x8FFF) {
            return instruction_memory[address];
        } else {
            error_dsp("Invalid DSP instruction memory address: 0x%04x", address);
            return 0;
        }
    }

    void write_instruction(u16 address, u16 value) {
        if (address <= 0x0FFF) {
            instruction_memory[address] = value;
        } else if (address >= 0x8000 && address <= 0x8FFF) {
            error_dsp("Cannot write to IROM at address: 0x%04x", address);
        } else {
            error_dsp("Invalid DSP instruction memory address: 0x%04x", address);
        }
    }

    u16 read_data(u16 address) {
        if (address <= 0x0FFF) {
            return data_memory[address];
        } else if (address >= 0x1000 && address <= 0x17FF) {
            return data_memory[address];
        } else {
            error_dsp("Invalid DSP data memory address: 0x%04x", address);
            return 0;
        }
    }

    void write_data(u16 address, u16 value) {
        if (address <= 0x0FFF) {
            data_memory[address] = value;
        } else if (address >= 0x1000 && address <= 0x17FF) {
            error_dsp("Cannot write to COEF memory at address: 0x%04x", address);
        } else {
            error_dsp("Invalid DSP data memory address: 0x%04x", address);
        }
    }

    void upload_iram(u16[] data) {
        if (data.length > 0x1000) {
            error_dsp("Data length exceeds IRAM size: %s > %s", data.length, 0x1000);
        }

        for (size_t i = 0; i < data.length; i++) {
            log_dsp("Uploading to IRAM[0x%04x] = 0x%04x", i, data[i]);
            instruction_memory[i] = data[i];
        }

        log_dsp("Uploaded %s words to IRAM", data.length);
    }

    void upload_irom(u16[] data) {
        if (data.length > 0x1000) {
            error_dsp("Data length exceeds IROM size: %s > %s", data.length, 0x1000);
        }

        for (size_t i = 0; i < data.length; i++) {
            log_dsp("Uploading to IROM[0x%04x] = 0x%04x", 0x8000 + i, data[i]);
            instruction_memory[0x8000 + i] = data[i];
        }

        log_dsp("Uploaded %s words to IROM", data.length);
    }

    void upload_dram(u16[] data) {
        if (data.length > 0x1000) {
            error_dsp("Data length exceeds DRAM size: %s > %s", data.length, 0x1000);
        }

        for (size_t i = 0; i < data.length; i++) {
            log_dsp("Uploading to DRAM[0x%04x] = 0x%04x", i, data[i]);
            data_memory[i] = data[i];
        }

        log_dsp("Uploaded %s words to DRAM", data.length);
    }

    void upload_coef(u16[] data) {
        if (data.length > 0x800) {
            error_dsp("Data length exceeds COEF size: %s > %s", data.length, 0x800);
        }

        for (size_t i = 0; i < data.length; i++) {
            log_dsp("Uploading to COEF[0x%04x] = 0x%04x", 0x1000 + i, data[i]);
            data_memory[0x1000 + i] = data[i];
        }

        log_dsp("Uploaded %s words to COEF", data.length);
    }
}