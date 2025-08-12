module emu.hw.dsp.jit.emission.code;

import core.bitop;
import emu.hw.dsp.state;
import gallinule.x86;
import std.conv;
import util.log;
import util.number;

// Import x86 registers
public import gallinule.x86 : rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp, r8, r9, r10, r11, r12, r13, r14, r15;

final class DspCode {
    Block!true block;
    alias block this;

    enum MAX_INSTRUCTIONS_PER_BLOCK = 10;
    private int current_max_instructions_per_block = MAX_INSTRUCTIONS_PER_BLOCK;

    this() {
        block = Block!true();
    }

    void init() {
        block.reset();
        this.emit_prologue();
    }

    void emit_prologue() {
        this.push(rbp);
        this.mov(rbp, rsp);

        foreach (reg; [rbx, r12, r13, r14, r15]) {
            this.push(reg);
        }
    }

    void emit_epilogue() {
        foreach (reg; [r15, r14, r13, r12, rbx]) {
            this.pop(reg);
        }

        this.pop(rbp);
        this.ret();
    }
    
    u8[] get() {
        emit_epilogue();

        auto code = block.finalize();
        ubyte[] copy = new ubyte[code.length];
        copy[0 .. code.length] = code;

        return copy;
    }

    int label_counter = 0;
    string fresh_label() {
        return "dsp_label_" ~ to!string(label_counter++);
    }

    int stack_alignment;
    void push(R64 reg) {
        block.push(reg);
        stack_alignment += 8;
    }

    void pop(R64 reg) {
        block.pop(reg);
        stack_alignment -= 8;
    }

    void enter_single_step_mode() {
        this.current_max_instructions_per_block = 1;
    }

    void exit_single_step_mode() {
        this.current_max_instructions_per_block = MAX_INSTRUCTIONS_PER_BLOCK;
    }

    int get_max_instructions_per_block() {
        return current_max_instructions_per_block;
    }

    Address!16 get_pc_addr() {
        return wordPtr(rdi, cast(int) DspState.pc.offsetof);
    }
}