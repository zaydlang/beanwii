module ui.reng.jit.debugger;

version (linux) {
import core.stdc.string;
import emu.hw.wii;
import raylib;
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
    private size_t current_pass_index = 0;
    private bool button_clicked = false;
    // void unimplemented(nk_context* ctx) {

    // }

    // void setup() {
    // }

    // void update(nk_context* ctx) {
    // }
}
}