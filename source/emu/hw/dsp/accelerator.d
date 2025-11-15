module emu.hw.dsp.accelerator;

import emu.hw.memory.strategy.memstrategy;
import util.number;
import util.log;
import std.stdio;

final class DSPAccelerator {
    u16[16] adpcm_coefficients; // 0xFFA0-0xFFAF
    u16 format_register;        // 0xFFD1
    u16 unknown1_register;      // 0xFFD2
    u16 raw_data_register;      // 0xFFD3
    u32 start_addr;             // 0xFFD4/0xFFD5
    u32 end_addr;               // 0xFFD6/0xFFD7
    u32 current_addr;           // 0xFFD8/0xFFD9
    u16 pred_scale_register;    // 0xFFDA
    u16 yn1_register;           // 0xFFDB
    u16 yn2_register;           // 0xFFDC
    u16 gain_register;          // 0xFFDE
    u16 acin_register;          // 0xFFDF
    
    Mem mem;

    this() {
        adpcm_coefficients[] = 0;
        format_register = 0;
        unknown1_register = 3;
        raw_data_register = 0;
        start_addr = 0;
        end_addr = 0;
        current_addr = 0;
        pred_scale_register = 0;
        yn1_register = 0;
        yn2_register = 0;
        gain_register = 0;
        acin_register = 0;
    }

    u16 read_register(u16 address) {
        log_accelerator("Read from DSP accelerator address 0x%04X", address);
        switch (address) {
        case 0xFFA0: .. case 0xFFAF:
            return adpcm_coefficients[address - 0xFFA0];
        case 0xFFD1:
            return format_register;
        case 0xFFD2:
            return unknown1_register;
        case 0xFFD3:
            return raw_data_register;
        case 0xFFD4:
            return cast(u16) (start_addr >> 16);
        case 0xFFD5:
            return cast(u16) (start_addr & 0xFFFF);
        case 0xFFD6:
            return cast(u16) (end_addr >> 16);
        case 0xFFD7:
            return cast(u16) (end_addr & 0xFFFF);
        case 0xFFD8:
            return cast(u16) (current_addr >> 16);
        case 0xFFD9:
            return cast(u16) (current_addr & 0xFFFF);
        case 0xFFDA:
            return pred_scale_register;
        case 0xFFDB:
            return yn1_register;
        case 0xFFDC:
            return yn2_register;
        case 0xFFDD:
            return decode_next_sample();
        case 0xFFDE:
            return gain_register;
        case 0xFFDF:
            return acin_register;
        default:
            error_dsp("DSP accelerator read from unhandled address 0x%04X", address);
            return 0;
        }
    }

    void write_register(u16 address, u16 value) {
        switch (address) {
        case 0xFFA0: .. case 0xFFAF:
            log_accelerator("ADPCM coefficient write to 0x%04X: 0x%04X", address, value);
            adpcm_coefficients[address - 0xFFA0] = value;
            break;
        case 0xFFD1:
            log_accelerator("FORMAT register write: 0x%04X", value);
            format_register = value;
            break;
        case 0xFFD2:
            log_accelerator("UNKNOWN1 register write: 0x%04X", value);
            unknown1_register = value;
            break;
        case 0xFFD3:
            log_accelerator("RAW_DATA register write: 0x%04X", value);
            raw_data_register = value;
            break;
        case 0xFFD4:
            log_accelerator("START_ADDR_HIGH register write: 0x%04X", value);
            start_addr = (start_addr & 0x0000FFFF) | (cast(u32) value << 16);
            break;
        case 0xFFD5:
            log_accelerator("START_ADDR_LOW register write: 0x%04X", value);
            start_addr = (start_addr & 0xFFFF0000) | value;
            break;
        case 0xFFD6:
            log_accelerator("END_ADDR_HIGH register write: 0x%04X", value);
            end_addr = (end_addr & 0x0000FFFF) | (cast(u32) value << 16);
            break;
        case 0xFFD7:
            log_accelerator("END_ADDR_LOW register write: 0x%04X", value);
            end_addr = (end_addr & 0xFFFF0000) | value;
            break;
        case 0xFFD8:
            // TODO: where should i put this
            done = false;
            
            log_accelerator("CURRENT_ADDR_HIGH register write: 0x%04X", value);
            current_addr = (current_addr & 0x0000FFFF) | (cast(u32) value << 16);
            break;
        case 0xFFD9:
            log_accelerator("CURRENT_ADDR_LOW register write: 0x%04X", value);
            current_addr = (current_addr & 0xFFFF0000) | value;
            break;
        case 0xFFDA:
            log_accelerator("PRED_SCALE register write: 0x%04X", value);
            pred_scale_register = value;
            break;
        case 0xFFDB:
            log_accelerator("YN1 register write: 0x%04X", value);
            yn1_register = value;
            break;
        case 0xFFDC:
            log_accelerator("YN2 register write: 0x%04X", value);
            yn2_register = value;
            // dump_memory_range();
            break;
        case 0xFFDE:
            log_accelerator("GAIN register write: 0x%04X", value);
            gain_register = value;
            break;
        case 0xFFDF:
            log_accelerator("ACIN register write: 0x%04X", value);
            acin_register = value;
            break;
        default:
            error_dsp("DSP accelerator write to unhandled address 0x%04X (value 0x%04X)", address, value);
            break;
        }
    }
    
    void connect_mem(Mem mem) {
        this.mem = mem;
    }
    
    private void dump_memory_range() {
        u32 dump_current_addr = current_addr;
        u32 dump_end_addr = end_addr;
        
        dump_current_addr >>= 1;
        dump_end_addr     >>= 1;
        
        log_accelerator("Memory dump from 0x%08X to 0x%08X:", dump_current_addr, dump_end_addr);
        
        if (dump_current_addr > dump_end_addr) {
            log_accelerator("Invalid address range - current > end");
            return;
        }
        
        string filename = "accelerator_memory_dump.bin";
        auto file = File(filename, "wb");
        
        for (u32 addr = dump_current_addr; addr <= dump_end_addr; addr++) {
            u8 byte_val = mem.physical_read_u8(addr);
            file.rawWrite([byte_val]);
        }
        
        file.close();
        log_accelerator("Memory dumped to %s (%d bytes)", filename, dump_end_addr - dump_current_addr + 1);
    }

    bool done;
    private u16 decode_next_sample() {
        if (done) {
            return 0;
        }

        if (current_addr >= end_addr) {
            done = true;
            current_addr = start_addr;
            return 0;
        }
        
        u8 scale = pred_scale_register & 0xF;
        u8 coef_idx = (pred_scale_register >> 4) & 0x7;
        
        if (coef_idx >= 8) coef_idx = 0;
        
        s16 coef1 = cast(s16) adpcm_coefficients[coef_idx * 2];
        s16 coef2 = cast(s16) adpcm_coefficients[coef_idx * 2 + 1];
        
        u32 byte_addr = current_addr >> 1;
        u8 memory_byte = mem.physical_read_u8(byte_addr);
        s8 temp;
        
        if (current_addr & 1) {
            temp = cast(s8) (memory_byte & 0xF);
        } else {
            temp = cast(s8) (memory_byte >> 4);
        }
        
        if (temp >= 8) temp -= 16;
        
        s32 val32 = ((1 << scale) * temp) + ((0x400 + coef1 * cast(s16) yn1_register + coef2 * cast(s16) yn2_register) >> 11);
        
        s16 val = cast(s16) (val32 > 0x7FFF ? 0x7FFF : (val32 < -0x7FFF ? -0x7FFF : val32));
        
        yn2_register = yn1_register;
        yn1_register = cast(u16) val;
        
        current_addr++;
        
        if ((current_addr & 15) == 0) {
            pred_scale_register = mem.physical_read_u8(current_addr >> 1);
            current_addr += 2;
        }
        
        return cast(u16) val;
    }
}