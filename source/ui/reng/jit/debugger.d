module ui.reng.jit.debugger;

version (linux) {
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
import std.range;

final class JitDebugger {
    private WiiDebugger wii_debugger;

    this(WiiDebugger wii_debugger) {
        this.wii_debugger = wii_debugger;
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

	private nk_text_edit sandbox_text_edit;
    private enum SANDBOX_EDITOR_SIZE = 1000;
    private char[SANDBOX_EDITOR_SIZE] sandbox_text_buffer;

    void generate_recipe() {
    }

    void unimplemented() {

    }

    void setup() {
        nk_textedit_init_fixed(&sandbox_text_edit, sandbox_text_buffer.ptr, SANDBOX_EDITOR_SIZE - 1);
    }
        
    void update(nk_context* ctx) {
        static foreach (pass; passes) {
            if (nk_button_label(ctx, pass.name.ptr)) {
                pass.run();
            }
        }

        nk_edit_buffer(ctx, nk_edit_types.NK_EDIT_FIELD, &sandbox_text_edit, &nk_filter_default);
    }
}
}