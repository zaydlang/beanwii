module emu.hw.broadway.jit.emission.code;

import core.bitop;
import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.x86;
import util.log;
import util.number;
import xbyak;

final class Code : CodeGenerator {
    static const CPU_BASE_REG = rdi;

    this() {
        free_all_registers();
    }

    Reg64 get_reg(GuestReg reg) {
        auto offset = get_reg_offset(reg);
        auto host_reg = allocate_register();

        this.mov(host_reg, dword [rdi + cast(int) offset]);
        return host_reg;
    }

    void set_reg(GuestReg reg, Reg64 host_reg) {
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
    Reg64 allocate_register() {
        if (allocated_regs == 0xFFFF) {
            error_jit("No free registers available");
        }

        int reg = core.bitop.bsf(allocated_regs);
        allocated_regs |= 1 << reg;
        return u16_to_reg64(cast(u16) reg);
    }

    void reserve_register(Reg64 reg) {
        allocated_regs |= 1 << reg64_to_u16(reg);
    }

    void free_register(Reg64 reg) {
        allocated_regs &= ~(1 << reg64_to_u16(reg));
    }

    void free_all_registers() {
        allocated_regs = 0;
    }
}