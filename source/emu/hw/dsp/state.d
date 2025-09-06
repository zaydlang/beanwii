module emu.hw.dsp.state;

import emu.hw.dsp.jit.emission.flags;
import util.bitop;
import util.number;

struct DspState {
    u16[4] ar;
    u16[4] ix;
    u16[4] wr;
    u16[4] st;
    u16 config;
    u16 sr_upper;

    u16 prod_hi;
    u16 prod_m1;
    u16 prod_m2;
    u16 prod_lo;

    union LongAcumulator {
        struct {
            u16 lo;
            u16 md;
            u16 hi;
            u16 padding;
        };

        u64 full;
    };

    union ShortAccumulator {
        struct {
            u16 lo;
            u16 hi;
        };

        u32 full;
    };

    LongAcumulator[2] ac;
    ShortAccumulator[2] ax;

    FlagState flag_state;
    
    u16 pc;

    void set_reg(int index, u16 value) {
        final switch (index) {
        case 0:
        case 1:
        case 2:
        case 3:
            ar[index] = value;
            break;
        
        case 4:
        case 5:
        case 6:
        case 7:
            ix[index - 4] = value;
            break;

        case 8:
        case 9:
        case 10:
        case 11:
            wr[index - 8] = value;
            break;
        
        case 12:
        case 13:
        case 15:
            st[index - 12] = value;
            break;

        case 14:
            // cant write to $st2 directly
            break;
        
        case 16:
        case 17:
            ac[index - 16].hi = sext_16(cast(u16) (value & 0xff), 8);
            break;
        
        case 18:
            config = value;
            break;
        
        case 19:
            sr_upper = (value >> 8) & ~1;
            flag_state.set(value & 0xff);
            break;
        
        case 20:
            prod_lo = value;
            break;

        case 21:
            prod_m1 = value;
            break;
        
        case 22:
            prod_hi = value & 0xff;
            break;

        case 23:
            prod_m2 = value;
            break;

        case 24:
        case 25:
            ax[index - 24].lo = value;
            break;
        
        case 26:
        case 27:
            ax[index - 26].hi = value;
            break;

        case 28:
        case 29:
            ac[index - 28].lo = value;
            break;
        
        case 30:
        case 31:
            ac[index - 30].md = value;
            break;
        }
    }

    u16 get_reg(int index) {
        final switch (index) {
        case 0:
        case 1:
        case 2:
        case 3:
            return ar[index];
        
        case 4:
        case 5:
        case 6:
        case 7:
            return ix[index - 4];
        
        case 8:
        case 9:
        case 10:
        case 11:
            return wr[index - 8];
        
        case 12:
        case 13:
        case 14:
        case 15:
            return st[index - 12];
        
        case 16:
        case 17:
            return ac[index - 16].hi;
        
        case 18:
            return config;
        
        case 19:
            return cast(ushort) ((sr_upper << 8) | flag_state.get());
        
        case 20:
            return prod_lo;

        case 21:
            return prod_m1;
        
        case 22:
            return prod_hi;

        case 23:
            return prod_m2;

        case 24:
        case 25:
            return ax[index - 24].lo;
        
        case 26:
        case 27:
            return ax[index - 26].hi;

        case 28:
        case 29:
            return ac[index - 28].lo;
        
        case 30:
        case 31:
            return ac[index - 30].md;
        }
    }
}