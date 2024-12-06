module emu.hw.broadway.hle;

import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import util.endian;
import util.log;
import util.number;

alias HleFunc = void function(void* context, BroadwayState* state);

enum HLE_ADDRESS_BASE = 0x2000_0000;
enum HLE_MAX_FUNCS    = 32;

final class HleContext {
    private HleInfo[] hle_infos;
    private size_t    num_hle_functions;
    private Mem*      mem;

    this(Mem* mem) {
        this.mem               = mem;
        this.hle_infos         = [];
        this.num_hle_functions = 0;
    }

    private struct HleInfo {
        void*   context; // passed to the hle function pointer
        HleFunc func;
        u32     guest_address;
    }

    // returns the address of the hle function
    public u32 add_hle_func(HleFunc hle_func, void* context) {
        // 0x2xxx_xxxx is an unused region of memory.
        // so, we will put the addresses of any hle functions in this range.
        u32 hle_func_address = generate_hle_func_address();

        this.hle_infos ~= HleInfo(
            context,
            hle_func,
            hle_func_address
        );

        int hle_function_id = generate_hle_func_id();

        import util.array;
        // patch the code to add an HLE opcode in memory
        mem.write_be_u32(hle_func_address, generate_hle_opcode(hle_function_id));
        log_apploader("%x %x", cast(u64) mem, mem.read_be_u32(hle_func_address));
                log_slowmem("verify: 0x%08x", mem.hle_trampoline.read_be!u32(0));

        this.num_hle_functions++;
        return hle_func_address;
    }

    public void hle_handler(BroadwayState* broadway_state, int function_id) {
        hle_infos[function_id].func(hle_infos[function_id].context, broadway_state);
    }

    private u32 generate_hle_func_address() {
        return HLE_ADDRESS_BASE + cast(u32) num_hle_functions * 4;
    }

    private int generate_hle_func_id() {
        return cast(int) num_hle_functions;
    }

    private u32 generate_hle_opcode(int hle_function_id) {
        // an HLE opcode format is quite simple. it has a primary opcode of 0x1F, and a secondary
        // opcode of 0x357. the hle_function_id is stored in bits 21-25.
        assert(hle_function_id <= 31);
        assert(hle_function_id >= 0);
        
        return 0x7C0006AE | (hle_function_id << 21);
    }
}

public void hle_os_report(void* context, BroadwayState* state) {
    import std.conv;

    // shoot me, i have to implement printf

    Mem* mem = cast(Mem*) context;
    u32 string_ptr = state.gprs[3];

    string output = "";
    char next_char;


    // gprs[3] is the string pointer
    // gprs[4..] are the arguments
    int current_gpr_arg = 4; 

    do {
        next_char = mem.read_be_u8(string_ptr++);
        if (next_char == '%') {
            char format_type = mem.read_be_u8(string_ptr++);
                switch (format_type) {
                case 's':
                    char inserted_char;
                    u32 current_address = state.gprs[current_gpr_arg++];
                    do {
                        inserted_char = mem.read_be_u8(current_address++);
                        output ~= inserted_char;
                    } while (inserted_char != 0);
                    break;
                
                case 'd':
                    output ~= to!string(state.gprs[current_gpr_arg++]);
                    break;
                
                case 'x':
                    output ~= to!string(state.gprs[current_gpr_arg++], 16);
                    break;

                default:
                    output ~= format_type;
                    break;
            }
        } else {
            output ~= next_char;
        }
    } while (next_char != 0);

    log_os_report(output);

    return;
}