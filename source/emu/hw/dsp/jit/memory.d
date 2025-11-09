module emu.hw.dsp.jit.memory;

import util.bitop;
import util.number;
import util.log;

final class DspMemory {
    u16[0x10000] instruction_memory;
    u16[0x1800] data_memory;

    this() {
        load_coef_memory();
    }

    private void load_coef_memory() {
        import std.file : exists, read;
        import std.path : buildPath;

        string coef_path = buildPath("roms", "dsp_coef.bin");
        
        if (!exists(coef_path)) {
            log_dsp("DSP COEF file not found at %s, using zeroed COEF memory", coef_path);
            return;
        }

        try {
            ubyte[] file_data = cast(ubyte[]) read(coef_path);
            
            if (file_data.length != 0x1000) {
                error_dsp("DSP COEF file size mismatch: expected 4096 bytes, got %d bytes", file_data.length);
                return;
            }

            u16[] coef_data = new u16[0x800];
            for (size_t i = 0; i < 0x800; i++) {
                coef_data[i] = (cast(u16) file_data[i * 2] << 8) | file_data[i * 2 + 1];
            }

            upload_coef(coef_data);
            log_dsp("Loaded DSP COEF memory from %s", coef_path);
        } catch (Exception e) {
            error_dsp("Failed to load DSP COEF file: %s", e.msg);
        }
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