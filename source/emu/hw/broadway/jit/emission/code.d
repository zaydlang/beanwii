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
    private bool mmu_enabled;
    
    u8[] slow_access_bitmap = new u8[1 << 24];
    
    this(JitConfig config) {
        this.config = config;
        block = Block!true();

        free_all_registers();
    }

    public void set_mmu_enabled(bool enabled) {
        this.mmu_enabled = enabled;
    }

    public bool get_mmu_enabled() {
        return this.mmu_enabled;
    }

    public bool force_slow_access(u32 pc) {
        return true;
        import app : g_fastmem_start_addr, g_fastmem_end_addr;
        
        pc &= 0x1fff_ffff;

        u32 bit_index = pc >> 2;
        u32 byte_index = bit_index >> 3;
        u32 bit_offset = bit_index & 7;

        log_memory("Checking slow access for PC %08x: byte_index=%d, bit_offset=%d, value=%d", pc, byte_index, bit_offset, (slow_access_bitmap[byte_index] >> bit_offset) & 1);
        return (slow_access_bitmap[byte_index] >> bit_offset) & 1;
    }
    
    public void mark_slow_access(u32 pc) {
        log_memory("Marking slow access for PC %08x", pc);
        pc &= 0x1fff_ffff;

        u32 bit_index = pc >> 2;
        u32 byte_index = bit_index >> 3;
        u32 bit_offset = bit_index & 7;

        slow_access_bitmap[byte_index] |= 1 << bit_offset;
    }
    
    public void clear_slow_access(u32 pc) {
        log_memory("Clearing slow access for PC %08x", pc);
        pc &= 0x1fff_ffff;

        u32 bit_index = pc >> 2;
        u32 byte_index = bit_index >> 3;
        u32 bit_offset = bit_index & 7;

        slow_access_bitmap[byte_index] &= ~(1 << bit_offset);
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

    R32 allocate_register_prefer(R32 preferred) {
        int preferred_index = reg32_to_u16(preferred);
        if ((allocated_regs & (1 << preferred_index)) == 0) {
            allocated_regs |= 1 << preferred_index;
            return preferred;
        } else {
            return allocate_register();
        }
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

    private bool fp_checked = false;
    private u32 first_fp_pc;
    
    public string get_epilogue_label() { 
        return "epilogue"; 
    }
    
    public void reset_fp_checked() {
        fp_checked = false;
    }
    
    public bool has_checked_fp() {
        return fp_checked;
    }
    
    public void mark_fp_checked() {
        fp_checked = true;
    }
    
    public void set_first_fp_pc(u32 pc) {
        first_fp_pc = pc;
    }
    
    public u32 get_first_fp_pc() {
        return first_fp_pc;
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
        if (guest_pc >= 0x8023f4e0 && guest_pc <= 0x8023f590) {
            return 1;
        }
        return current_max_instructions_per_block;
    }
}