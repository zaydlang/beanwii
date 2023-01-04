module emu.hw.broadway.jit.frontend.disassembler;

import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.frontend.opcode;
import emu.hw.broadway.jit.ir.ir;
import std.sumtype;
import util.bitop;
import util.log;
import util.number;

// void do_action(IR* ir, Word opcode) {
//     decode_jumptable[opcode >> 8](ir, opcode);
// }

// void emit_branch_exchange__THUMB()(IR* ir, Word opcode) {
//     GuestReg rm = cast(GuestReg) opcode[3..6];

//     IRVariable address    = ir.get_reg(rm);
//     IRVariable cpsr       = ir.get_reg(GuestReg.CPSR);
//     IRVariable thumb_mode = address & 1;

//     if (rm == GuestReg.PC) address = address - 2;
    
//     cpsr = cpsr & ~(1          << 5);
//     cpsr = cpsr |  (thumb_mode << 5);

//     ir.set_reg(GuestReg.CPSR, cpsr);

//     // thanks Kelpsy for this hilarious hack
//     address = address & ~((thumb_mode << 1) ^ 3);
    
//     ir.set_reg(GuestReg.PC, address);
    
//     log_jit("Emitting bx r%d", rm);
// }

private void emit_addi(IR* ir, u32 opcode) {
    GuestReg rd = cast(GuestReg) opcode.bits(21, 25);
    GuestReg ra = cast(GuestReg) opcode.bits(16, 20);
    int simm = sext_32(opcode.bits(0, 15), 16);

    if (ra == 0) {
        ir.set_reg(rd, simm);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + simm);
    }
}

private void emit_addis(IR* ir, u32 opcode) {
    GuestReg rd = cast(GuestReg) opcode.bits(21, 25);
    GuestReg ra = cast(GuestReg) opcode.bits(16, 20);
    int simm = opcode.bits(0, 15); // no need to sext cuz it gets shifted by 16

    if (ra == 0) {
        ir.set_reg(rd, simm << 16);
    } else {
        IRVariable src = ir.get_reg(ra);
        ir.set_reg(rd, src + (simm << 16));
    }
}

public void emit(IR* ir, u32 opcode) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:  emit_addi (ir, opcode); break;
        case PrimaryOpcode.ADDIS: emit_addis(ir, opcode); break;

        default: error_jit("Unimplemented opcode: %x", opcode);
    }
}
