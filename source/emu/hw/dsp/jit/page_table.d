module emu.hw.dsp.jit.page_table;

import core.stdc.stdlib;
import util.number;

alias DspJitFunction = u32 function(void* dsp_state);

struct DspJitEntry {
    DspJitFunction func;
    u16 instruction_count;
    bool valid;
}

final class DspPageTable {
    DspJitEntry*[256] level1;

    private u32 make_key(u16 pc, u32 config_bitfield) {
        return (cast(u32) pc) | (config_bitfield << 16);
    }

    void reset() {
        for (int i = 0; i < 256; i++) {
            level1[i] = null;
        }
    }

    bool has(u16 pc, u32 config_bitfield) {
        u32 key = make_key(pc, config_bitfield);
        u8 high = (key >> 8) & 0xFF;
        u8 low = key & 0xFF;
        
        if (level1[high] is null) return false;
        return level1[high][low].valid;
    }

    bool has(u16 pc) {
        return has(pc, 0);
    }

    DspJitEntry get(u16 pc, u32 config_bitfield) {
        u32 key = make_key(pc, config_bitfield);
        u8 high = (key >> 8) & 0xFF;
        u8 low = key & 0xFF;
        
        assert(level1[high] !is null);
        return level1[high][low];
    }

    DspJitEntry get(u16 pc) {
        return get(pc, 0);
    }

    void put(u16 pc, u32 config_bitfield, DspJitEntry entry) {
        u32 key = make_key(pc, config_bitfield);
        u8 high = (key >> 8) & 0xFF;
        u8 low = key & 0xFF;
        
        if (level1[high] is null) {
            level1[high] = cast(DspJitEntry*) calloc(256, DspJitEntry.sizeof);
        }
        
        level1[high][low] = entry;
    }

    void put(u16 pc, DspJitEntry entry) {
        put(pc, 0, entry);
    }

    void invalidate(u16 pc, u32 config_bitfield) {
        u32 key = make_key(pc, config_bitfield);
        u8 high = (key >> 8) & 0xFF;
        u8 low = key & 0xFF;
        
        if (level1[high] !is null) {
            level1[high][low].valid = false;
        }
    }

    void invalidate(u16 pc) {
        invalidate(pc, 0);
    }

    void invalidate_range(u16 start, u16 end) {
        for (u16 pc = start; pc <= end; pc++) {
            invalidate(pc, 0);
            invalidate(pc, 1);
        }
    }
}