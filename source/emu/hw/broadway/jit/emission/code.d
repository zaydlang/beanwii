module emu.hw.broadway.jit.emission.code;

import core.bitop;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.x86;
import std.conv;
import util.log;
import util.number;
import xbyak;

final class Code : CodeGenerator {
    static const CPU_BASE_REG = rdi;

    this() {
        free_all_registers();
    }

    void init() {
        this.reset();
        this.free_all_registers();
        this.reserve_register(edi);
        
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
    
    T get_function(T)() {
        this.emit_epilogue();

        assert(!this.hasUndefinedLabel());
        return cast(T) this.getCode();
    }

    Reg32 get_reg(GuestReg reg) {
        auto offset = get_reg_offset(reg);
        auto host_reg = allocate_register();

        this.mov(host_reg, dword [rdi + cast(int) offset]);
        return host_reg;
    }

    void set_reg(GuestReg reg, Reg32 host_reg) {
        auto offset = get_reg_offset(reg);
        this.mov(dword [rdi + cast(int) offset], host_reg);
    }

    void set_reg(GuestReg reg, int value) {
        auto offset = get_reg_offset(reg);
        this.mov(dword [rdi + cast(int) offset], value);
    }

    Address get_address(GuestReg reg) {
        auto offset = get_reg_offset(reg);
        return dword [rdi + cast(int) offset];
    }

    // bitfield
    u16 allocated_regs;
    Reg32 allocate_register() {
        if (allocated_regs == 0xFFFF) {
            error_jit("No free registers available");
        }

        int reg = core.bitop.bsf(~allocated_regs);
        allocated_regs |= 1 << reg;
        return u16_to_reg32(cast(u16) reg);
    }

    void reserve_register(Reg32 reg) {
        allocated_regs |= 1 << reg32_to_u16(reg);
    }

    void free_register(Reg32 reg) {
        allocated_regs &= ~(1 << reg32_to_u16(reg));
    }

    void free_all_registers() {
        allocated_regs = 0;
    }

    int label_counter = 0;
    string fresh_label() {
        return "label_" ~ to!string(label_counter++);
    }
}