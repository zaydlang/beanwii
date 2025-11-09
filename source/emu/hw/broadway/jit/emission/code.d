module emu.hw.broadway.jit.emission.code;

import core.bitop;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.jit;
import gallinule.x86;
import std.conv;
import util.log;
import util.number;
import util.x86;

final class Code {
    Block!true block;
    alias block this;

    enum MAX_INSTRUCTIONS_PER_BLOCK = 20;
    private int current_max_instructions_per_block = MAX_INSTRUCTIONS_PER_BLOCK;

    static const CPU_BASE_REG = rdi;

    JitConfig config;
    
    this(JitConfig config) {
        this.config = config;
        block = Block!true();

        free_all_registers();
    }

    u8* code_ptr;

    void init() {
        stack_alignment = 0;
        block.reset();

        this.free_all_registers();        
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
        return block.finalize();
    }

    R32 get_reg(GuestReg reg) {
        auto offset = get_reg_offset(reg);
        auto host_reg = allocate_register();

        this.mov(host_reg, dwordPtr(rdi, cast(int) offset));
        return host_reg;
    }

    R64 get_fpr(GuestReg reg) {
        auto offset = get_reg_offset(reg);
        auto host_reg = allocate_register().cvt64();

        this.mov(host_reg, qwordPtr(rdi, cast(int) offset));
        return host_reg;
    }

    void get_ps(GuestReg reg, XMM dest) {
        auto offset = get_reg_offset(reg);
        this.movupd(dest, xmmwordPtr(rdi, cast(int) offset));
    }

    void set_reg(GuestReg reg, R32 host_reg) {
        auto offset = get_reg_offset(reg);
        this.mov(dwordPtr(rdi, cast(int) offset), host_reg);
    }

    void set_reg(GuestReg reg, int value) {
        auto offset = get_reg_offset(reg);
        this.mov(dwordPtr(rdi, cast(int) offset), value);
    }

    void set_fpr(GuestReg reg, R64 host_reg) {
        auto offset = get_reg_offset(reg);
        this.mov(qwordPtr(rdi, cast(int) offset), host_reg);
    }

    void set_ps(GuestReg reg, XMM src) {
        auto offset = get_reg_offset(reg);
        this.movupd(xmmwordPtr(rdi, cast(int) offset), src);
    }

    Address!32 get_address(GuestReg reg) {
        auto offset = get_reg_offset(reg);
        return dwordPtr(rdi, cast(int) offset);
    }

    // bitfield
    u16 allocated_regs;
    R32 allocate_register() {
        if (allocated_regs == 0xFFFF) {
            error_jit("No free registers available");
        }

        int reg = core.bitop.bsf(~allocated_regs);
        allocated_regs |= 1 << reg;
        return u16_to_reg32(cast(u16) reg);
    }

    void reserve_register(R32 reg) {
        allocated_regs |= 1 << reg32_to_u16(reg);
    }

    void free_register(R32 reg) {
        allocated_regs &= ~(1 << reg32_to_u16(reg));
    }

    void free_all_registers() {
        allocated_regs = 0;
        this.reserve_register(edi);
    }

    int label_counter = 0;
    string fresh_label() {
        return "label_" ~ to!string(label_counter++);
    }

    int stack_alignment;
    void push(R64 reg) {
        block.push(reg);
        stack_alignment += 8;
    }

    void push(R32 reg) {
        block.push(reg.cvt64());
        stack_alignment += 4;
    }

    void pop(R64 reg) {
        block.pop(reg);
        stack_alignment -= 8;
    }

    void pop(R32 reg) {
        block.pop(reg.cvt64());
        stack_alignment -= 4;
    }

    bool in_stack_alignment_context;
    bool did_align_stack;

    // this is used for function calls
    void enter_stack_alignment_context() {
        assert(!in_stack_alignment_context);

        // anticipate the function call
        stack_alignment += 8;

        in_stack_alignment_context = true;
        if (stack_alignment % 16 != 0) {
            sub(rsp, 8);
            did_align_stack = true;
        } else {
            did_align_stack = false;
        }
    }

    void exit_stack_alignment_context() {
        assert(in_stack_alignment_context);

        if (did_align_stack) {
            add(rsp, 8);
        }

        stack_alignment -= 8;

        in_stack_alignment_context = false;
    }

    void push_caller_saved_registers() {
        foreach (reg; [rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11]) {
            this.push(reg);
        }
    }

    void pop_caller_saved_registers() {
        foreach (reg; [r11, r10, r9, r8, rdi, rsi, rdx, rcx, rax]) {
            this.pop(reg);
        }
    }

    void pop_caller_saved_registers_except(R64 except) {
        foreach (reg; [r11, r10, r9, r8, rdi, rsi, rdx, rcx, rax]) {
            if (reg != except) {
                this.pop(reg);
            } else {
                this.add(rsp, 8);
                stack_alignment += 8;
            }
        }
    }

    u32 guest_pc;
    u32 get_guest_pc() {
        return guest_pc;
    }

    void set_guest_pc(u32 pc) {
        guest_pc = pc;
    }

    u64 current_offset() {
        return block.buffer.pos;
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
}