module emu.hw.broadway.jit.backend.x86_64.label;

import emu.hw.broadway.jit.ir.ir;
import std.conv;

string to_xbyak_label(IRLabel ir_label) {
    return "L" ~ to!string(ir_label.id);
}