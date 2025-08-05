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

    void reset() {
        for (int i = 0; i < 256; i++) {
            level1[i] = null;
        }
    }

    bool has(u16 pc) {
        u8 high = (pc >> 8) & 0xFF;
        u8 low = pc & 0xFF;
        
        if (level1[high] is null) return false;
        return level1[high][low].valid;
    }

    DspJitEntry get(u16 pc) {
        u8 high = (pc >> 8) & 0xFF;
        u8 low = pc & 0xFF;
        
        assert(level1[high] !is null);
        return level1[high][low];
    }

    void put(u16 pc, DspJitEntry entry) {
        u8 high = (pc >> 8) & 0xFF;
        u8 low = pc & 0xFF;
        
        if (level1[high] is null) {
            level1[high] = cast(DspJitEntry*) calloc(256, DspJitEntry.sizeof);
        }
        
        level1[high][low] = entry;
    }

    void invalidate(u16 pc) {
        u8 high = (pc >> 8) & 0xFF;
        u8 low = pc & 0xFF;
        
        if (level1[high] !is null) {
            level1[high][low].valid = false;
        }
    }

    void invalidate_range(u16 start, u16 end) {
        for (u16 pc = start; pc <= end; pc++) {
            invalidate(pc);
        }
    }
}