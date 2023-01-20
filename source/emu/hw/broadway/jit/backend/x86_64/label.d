module emu.hw.broadway.jit.backend.x86_64.label;

import emu.hw.broadway.jit.ir.ir;
import std.conv;

string to_xbyak_label(IRLabel ir_label) {
    return "L" ~ to!string(ir_label.id);
}

size_t label_counter = 0;
string generate_unique_label() {
    return "Lunique" ~ to!string(label_counter++);
}
