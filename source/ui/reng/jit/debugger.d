module ui.reng.jit.debugger;

version (linux) {
import capstone;
import core.stdc.string;
import emu.hw.wii;
import nuklear;
import nuklear_ext;
import raylib;
import raylib_nuklear;
import re;
import re.gfx;
import re.math;
import re.ecs;
import re.ng.diag;
import re.util.interop;
import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.range;
import util.number;

final class JitDebugger {
    private WiiDebugger wii_debugger;
    private Capstone capstone;

    this(WiiDebugger wii_debugger) {
        this.wii_debugger = wii_debugger;
        this.capstone     = create(Arch.ppc, ModeFlags(Mode.bit32));
    }

    private struct Pass {
        string name;
        void function() run;
    }

    enum Pass[] passes = [
        Pass("Generate Recipe", &generate_recipe),
        Pass("Optimize GetReg", &unimplemented),
        Pass("Optimize SetReg", &unimplemented),
        Pass("Constant Folding", &unimplemented),
        Pass("Dead Code Elimination", &unimplemented),
        Pass("Impose x86 Conventions", &unimplemented),
        Pass("Allocate Registers", &unimplemented),
        Pass("Optimize Dead Moves", &unimplemented),
        Pass("Code Emission", &unimplemented)
    ];

    void generate_recipe() {
    }

    void unimplemented() {
    }

    void setup() {
    }
        
    void update(nk_context* ctx) {
        u32 pc = wii_debugger.get_pc();

        u32 instruction = wii_debugger.read_be_u32(pc);
        auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);

        size_t current_char = 0;
        foreach (instr; res) {
            string disassembled_instruction = format("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
            nk_label(ctx, disassembled_instruction.ptr, nk_text_alignment.NK_TEXT_LEFT);
        }

        static foreach (pass; passes) {
            if (nk_button_label(ctx, pass.name.ptr)) {
                pass.run();
            }
        }
    }
}
}