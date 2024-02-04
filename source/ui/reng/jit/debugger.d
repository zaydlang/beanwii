module ui.reng.jit.debugger;

version (linux) {
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
import ui.reng.wiidebugger;
import util.number;

final class JitDebugger {
    private WiiDebugger wii_debugger;
    private size_t current_pass_index = 0;
    private bool button_clicked = false;
    Pass[] passes;

    this(WiiDebugger wii_debugger) {
        this.wii_debugger = wii_debugger;

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
        auto disassembly = wii_debugger.disassemble_basic_block_at(pc);
        render_sandbox_string(ctx, disassembly);
    }

    void generate_recipe(nk_context* ctx) {
        u32 pc = wii_debugger.get_pc();
        string recipe = wii_debugger.generate_recipe(pc);
        render_sandbox_string(ctx, recipe);
    }

    void render_sandbox_string(nk_context* ctx, string str) {
        auto window_pos = nk_window_get_bounds(ctx);
    
        size_t padding = 5;

        size_t panel_x      = cast(size_t) window_pos.x + padding;
        size_t panel_y      = cast(size_t) window_pos.y + padding;
        size_t panel_width  = cast(size_t) window_pos.w - padding * 2;
        size_t panel_height = cast(size_t) window_pos.h - padding * 2;

        nk_command_buffer* canvas = nk_window_get_canvas(ctx);
        import std.stdio;
        // writefln("rect: %d %d %d %d", rect_x, 0, rect_width, height);

        // nk_fill_rect(canvas, nk_rect(cast(int) rect_x, 0, cast(int) rect_width, cast(int) height), 0, nk_rgb(0, 0, 0));

        nk_layout_row_dynamic(ctx, panel_height - panel_y, 1);
        if (nk_group_begin(ctx, "asdf", nk_panel_flags.NK_WINDOW_BORDER)) {
            nk_layout_row_dynamic(ctx, 20, 1);
            nk_label(ctx, str.ptr, nk_text_alignment.NK_TEXT_LEFT);
        }

        nk_group_end(ctx);
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