module ui.reng.jit.debugger;

version (linux) {
import capstone;
import core.stdc.string;
import emu.hw.wii;
import emu.hw.broadway.jit.ir.instruction;
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
    private size_t current_pass_index = 0;
    private bool button_clicked = false;
    Pass[] passes;

    this(WiiDebugger wii_debugger) {
        this.wii_debugger = wii_debugger;
        this.capstone     = create(Arch.ppc, ModeFlags(Mode.bit32));

        passes = [
            Pass("Disassemble", &this.disassemble),
            Pass("Generate Recipe", &this.generate_recipe),
            Pass("Optimize GetReg", &this.unimplemented),
            // Pass("Optimize SetReg", &unimplemented),
            // Pass("Constant Folding", &unimplemented),
            // Pass("Dead Code Elimination", &unimplemented),
            // Pass("Impose x86 Conventions", &unimplemented),
            // Pass("Allocate Registers", &unimplemented),
            // Pass("Optimize Dead Moves", &unimplemented),
            // Pass("Code Emission", &unimplemented)
        ];
    }

    private struct Pass {
        string name;
        void delegate(nk_context* ctx) run;
    }

    void disassemble(nk_context* ctx) {
        u32 pc = wii_debugger.get_pc();
        u32 instruction = wii_debugger.read_be_u32(pc);
        auto res = this.capstone.disasm((cast(ubyte*) &instruction)[0 .. 4], pc);

        size_t current_char = 0;
        foreach (instr; res) {
            string disassembled_instruction = format("0x%08x | %s\t\t%s", pc, instr.mnemonic, instr.opStr);
            nk_label(ctx, disassembled_instruction.ptr, nk_text_alignment.NK_TEXT_LEFT);
        }
    }

    void generate_recipe(nk_context* ctx) {
        u32 pc = wii_debugger.get_pc();
        u32 instruction = wii_debugger.read_be_u32(pc);
        string recipe = wii_debugger.generate_recipe(instruction);
        nk_label(ctx, recipe.ptr, nk_text_alignment.NK_TEXT_LEFT);
    }

    void unimplemented(nk_context* ctx) {

    }

    void setup() {
    }

    void update(nk_context* ctx) {
        bool old_button_clicked = button_clicked;
        button_clicked = cast(bool) nk_button_label(ctx, passes[current_pass_index + 1].name.ptr);

        if (button_clicked && !old_button_clicked) {
            current_pass_index++;
            current_pass_index = clamp(current_pass_index, 0, passes.length - 1);
        }

        passes[current_pass_index].run(ctx);
    }
}
}