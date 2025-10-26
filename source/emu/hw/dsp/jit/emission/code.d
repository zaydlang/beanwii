module emu.hw.dsp.jit.emission.code;

import core.bitop;
import emu.hw.dsp.jit.emission.config;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import gallinule.x86;
import std.conv;
import util.bitop;
import util.log;
import util.number;
import util.x86;

// Import x86 registers
public import gallinule.x86 : rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp, r8, r9, r10, r11, r12, r13, r14, r15;

final class DspCode {
    Block!true block;
    DspCodeConfig config;
    alias block this;

    enum MAX_INSTRUCTIONS_PER_BLOCK = 10;
    private int current_max_instructions_per_block = MAX_INSTRUCTIONS_PER_BLOCK;
    
    bool extension_handled = false;

    this() {
        block = Block!true();
    }

    void init(DspState* state) {
        block.reset();
        this.emit_prologue();
        free_all_registers();

        config.sr_SXM = state.sr_upper.bit(14 - 8);
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

    // bitfield
    u16 allocated_regs;
    R64 allocate_register() {
        if (allocated_regs == 0xFFFF) {
            error_jit("No free registers available");
        }

        int reg = core.bitop.bsf(~allocated_regs);
        allocated_regs |= 1 << reg;
        return u16_to_reg64(cast(u16) reg);
    }

    void reserve_register(R64 reg) {
        allocated_regs |= 1 << reg64_to_u16(reg);
    }

    void free_register(R64 reg) {
        allocated_regs &= ~(1 << reg64_to_u16(reg));
    }

    void deallocate_register(R64 reg) {
        free_register(reg);
    }

    void free_all_registers() {
        allocated_regs = 0;
        this.reserve_register(rdi);
        this.reserve_register(rsi);
    }

    Address!64 ac_full_address(int index) {
        log_dsp("offset = %d + %d * %d + %d", DspState.ac.offsetof, index, DspState.LongAcumulator.sizeof, DspState.LongAcumulator.full.offsetof);
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.full.offsetof;
        return qwordPtr(rdi, cast(int) offset);
    }

    Address!32 ac_hm_address(int index) {
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.md.offsetof;
        return dwordPtr(rdi, cast(int) offset);
    }

    Address!32 ac_ml_address(int index) {
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.lo.offsetof;
        return dwordPtr(rdi, cast(int) offset);
    }

    Address!16 ac_m_address(int index) {
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.md.offsetof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!16 ac_lo_address(int index) {
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.lo.offsetof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!32 ax_full_address(int index) {
        auto offset = DspState.ax.offsetof + index * DspState.ShortAccumulator.sizeof + DspState.ShortAccumulator.full.offsetof;
        return dwordPtr(rdi, cast(int) offset);
    }

    Address!16 ax_hi_address(int index) {
        auto offset = DspState.ax.offsetof + index * DspState.ShortAccumulator.sizeof + DspState.ShortAccumulator.hi.offsetof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!16 ax_lo_address(int index) {
        auto offset = DspState.ax.offsetof + index * DspState.ShortAccumulator.sizeof + DspState.ShortAccumulator.lo.offsetof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!16 ac_hi_address(int index) {
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.hi.offsetof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!8 ac_hi_address_u8(int index) {
        auto offset = DspState.ac.offsetof + index * DspState.LongAcumulator.sizeof + DspState.LongAcumulator.hi.offsetof;
        return bytePtr(rdi, cast(int) offset);
    }

    Address!16 ar_address(int index) {
        auto offset = DspState.ar.offsetof + index * u16.sizeof;
        return wordPtr(rdi, cast(int) offset);
    }
 
    Address!16 wr_address(int index) {
        auto offset = DspState.wr.offsetof + index * u16.sizeof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!16 ix_address(int index) {
        auto offset = DspState.ix.offsetof + index * u16.sizeof;
        return wordPtr(rdi, cast(int) offset);
    }

    Address!32 prod_lo_m1_address() {
        return dwordPtr(rdi, cast(int) DspState.prod_lo.offsetof);
    }

    Address!32 prod_m2_hi_address() {
        return dwordPtr(rdi, cast(int) DspState.prod_m2.offsetof);
    }

    Address!64 prod_full_address() {
        return qwordPtr(rdi, cast(int) DspState.prod_lo.offsetof);
    }

    Address!16 prod_m1_address() {
        return wordPtr(rdi, cast(int) DspState.prod_m1.offsetof);
    }
    
    Address!16 prod_lo_address() {
        return wordPtr(rdi, cast(int) DspState.prod_lo.offsetof);
    }

    Address!16 prod_hi_address() {
        return wordPtr(rdi, cast(int) DspState.prod_hi.offsetof);
    }

    Address!8 prod_hi_address_u8() {
        return bytePtr(rdi, cast(int) DspState.prod_hi.offsetof);
    }

    Address!16 prod_m2_address() {
        return wordPtr(rdi, cast(int) DspState.prod_m2.offsetof);
    }

    Address!8 sr_upper_address() {
        return bytePtr(rdi, cast(int) DspState.sr_upper.offsetof);
    }

    Address!64 call_stack_address() {
        return qwordPtr(rdi, cast(int) DspState.call_stack.offsetof);
    }

    Address!64 data_stack_address() {
        return qwordPtr(rdi, cast(int) DspState.data_stack.offsetof);
    }

    Address!64 loop_address_stack_address() {
        return qwordPtr(rdi, cast(int) DspState.loop_address_stack.offsetof);
    }

    Address!64 loop_counter_stack_address() {
        return qwordPtr(rdi, cast(int) DspState.loop_counter_stack.offsetof);
    }

    Address!8 call_stack_sp_address() {
        return bytePtr(rdi, cast(int) (DspState.call_stack.offsetof + DspState.Stack.sp.offsetof));
    }

    Address!8 data_stack_sp_address() {
        return bytePtr(rdi, cast(int) (DspState.data_stack.offsetof + DspState.Stack.sp.offsetof));
    }

    Address!8 loop_address_stack_sp_address() {
        return bytePtr(rdi, cast(int) (DspState.loop_address_stack.offsetof + DspState.Stack.sp.offsetof));
    }

    Address!8 loop_counter_stack_sp_address() {
        return bytePtr(rdi, cast(int) (DspState.loop_counter_stack.offsetof + DspState.Stack.sp.offsetof));
    }

    Address!64 data_memory_address() {
        return qwordPtr(rsi, cast(int) DspMemory.data_memory.offsetof);
    }

    Address!16 config_address() {
        return wordPtr(rdi, cast(int) DspState.config.offsetof);
    }
}