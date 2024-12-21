module emu.hw.broadway.jit.jit;

import capstone;
import dklib.khash;
import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.cpu;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import std.meta;
import util.bitop;
import util.log;
import util.number;
import util.ringbuffer;

alias ReadHandler  = u32 function(u32 address);
alias WriteHandler = void function(u32 address, u32 value);
alias HleHandler   = void function(int param);

struct JitContext {
    u32 pc;
    bool pse;
}

struct JitConfig {
    ReadHandler  read_handler8;
    ReadHandler  read_handler16;
    ReadHandler  read_handler32;
    ReadHandler  read_handler64;
    WriteHandler write_handler8;
    WriteHandler write_handler16;
    WriteHandler write_handler32;
    WriteHandler write_handler64;
    HleHandler   hle_handler;

    void*        mem_handler_context;
    void*        hle_handler_context;
}

final class Jit {
    private struct DebugState {
        BroadwayState state;
        u32 instruction;
    }

    private alias JitFunction = void function(BroadwayState* state);
    private alias JitHashMap = khash!(u32, JitFunction);
    private alias DebugRing  = RingBuffer!(DebugState);
    
    private Mem        mem;
    private JitHashMap jit_hash_map;
    private DebugRing  debug_ring;
    private Code       code;

    private CodeBlockTracker codeblocks;

    this(JitConfig config, Mem mem, size_t ringbuffer_size) {
        this.mem = mem;
        this.jit_hash_map = JitHashMap();
        this.debug_ring = new DebugRing(ringbuffer_size);
        this.code = new Code(config);
        this.codeblocks = new CodeBlockTracker();
    }

    // returns the number of instructions executed
    public u32 run(BroadwayState* state) {
        auto cached_func = jit_hash_map.require(state.pc, null);
        if (cached_func != null) {
            import std.stdio;
            
            cached_func(state);
        } else {
        code.init();
            // biglog = true;
            biglog = false;
        dicksinmyass = false;
            emit(code, mem, state.pc);
            u8[] bytes = code.get();
            // log_jit("Generated %d bytes of code for 0x%08x", bytes.length, state.pc);
            for (int i = 0; i < bytes.length - 8; i+= 8) {
                import std.stdio;
                // writefln("%02x %02x %02x %02x %02x %02x %02x %02x", bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3], bytes[i + 4], bytes[i + 5], bytes[i + 6], bytes[i + 7]);
            }
            auto ptr = codeblocks.put(bytes.ptr, bytes.length);
            auto func = cast(JitFunction) ptr;
                // auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
                // auto res = x86_capstone.disasm((cast(ubyte*) func)[0 .. bytes.length], 0);
                // foreach (instr; res) {
                    // import std.stdio;
                    
                    // writefln("0x%08x | %s\t\t%s", instr.address + cast(ulong) func, instr.mnemonic, instr.opStr);
                // }
if (instrument && biglog) {
            // import std.stdio;
            // log_state(state);
            // auto opcode = mem.read_be_u32(state.pc);
// log_jit("Unimplemented opcode: 0x%08x (at PC 0x%08x) (Primary: %x, Secondary: %x)", opcode, state.pc, opcode.bits(26, 31), opcode.bits(1, 10));
            // writefln("Opcode: %08x. Before. Paused emulation. >", mem.read_be_u32(state.pc));
            // readln;
            
            }
                

        if (state.pc == 0x800050f8) {
            int x = 2;
        }

        if (!dicksinmyass) 
        jit_hash_map[state.pc] = func;
        // log_state(state);
        // func(state);
        // log_instruction(mem.read_be_u32(state.pc), state.pc);
        if (dicksinmyass) {
            log_function("dicksinmyass");log_function("poopcode: 0x%08x (at PC 0x%08x) (Primary: %x, Secondary: %x)", mem.read_be_u32(state.pc), state.pc, mem.read_be_u32(state.pc).bits(26, 31), mem.read_be_u32(state.pc).bits(1, 10));
            log_instruction(mem.read_be_u32(state.pc), state.pc);
            // log_state(state);
        }
            func(state);
        if (dicksinmyass) {
            // log_state(state);
        }

        if (instrument && biglog) {
            // import std.stdio;
            // log_state(state);
            // writefln("Opcode: %08x. After. Paused emulation. >", mem.read_be_u32(state.pc));
            // readln;

            // jit_hash_map = JitHashMap();
        }
        }

        // make sure none of the ps are NaN
        for (int i = 0; i < 64; i++) {
            // float ps0 = *(cast(float*)&state.ps[i].ps0);
            // if (ps0 != ps0) {
                // error_broadway("NaN detected in PS[%d].ps0", i);
            // }

        }

        if (state.icache_flushed) {
            assert(state.icbi_address % 32 == 0);
            
            for (u32 i = 0; i < 32; i += 4) {
                jit_hash_map.remove(state.icbi_address + i);    
            }
            
            state.icache_flushed = false;
        }

        // auto func = code.get_function!JitFunction();
                // auto x86_capstone = create(Arch.x86, ModeFlags(Mode.bit64));
                // auto res = x86_capstone.disasm((cast(ubyte*) func)[0 .. code.getSize()], 0);
                // foreach (instr; res) {
                    // log_jit("0x%08x | %s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
                // }

        // if (mem.read_be_u32(state.pc) == 0x4d820020) {
            // int x = 2;
        // }
        // func(state);
        
        return 2;
    }

    private void log_instruction(u32 instruction, u32 pc) {
        auto x86_capstone = create(Arch.ppc, ModeFlags(Mode.bit64));
        auto res = x86_capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);
        foreach (instr; res) {
            log_broadway("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
        }
    }

    public void on_error() {
        // this.dump_debug_ring();
    }

    private void dump_debug_ring() {
        foreach (debug_state; this.debug_ring.get()) {
            log_instruction(debug_state.instruction, debug_state.state.pc - 4);
            log_state(&debug_state.state);
        }
    }
}