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

private void emit_addi(IR* ir, u32 opcode, u32 pc) {
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

private void emit_addis(IR* ir, u32 opcode, u32 pc) {
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

private void emit_b(IR* ir, u32 opcode, u32 pc) {
    bool aa = opcode.bit(1);
    bool lk = opcode.bit(0);
    int  li = opcode.bits(2, 25);

    u32 branch_address = sext_32(li, 24) << 2;
    if (!aa) branch_address += pc;

    if (lk) ir.set_reg(GuestReg.LR, pc);

    ir.set_reg(GuestReg.PC, branch_address);
}

private void emit_rlwinm(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = cast(GuestReg) opcode.bits(21, 25);
    GuestReg ra = cast(GuestReg) opcode.bits(16, 20);
    int      sh = opcode.bits(11, 15);
    int      mb = opcode.bits(6,  10);
    int      me = opcode.bits(1,  5);
    bool     rc = opcode.bit(0);

    assert (mb <= me);
    int mask = cast(int) ((cast(u64) 1) << (cast(u64) (mb - me + 1)) - 1) << mb;

    IRVariable result = ir.get_reg(rs);
    result = result.rol(sh) & mask;
    ir.set_reg(ra, result);

    if (rc) {
        error_broadway("rlwinm record bit unimplemented");
    }
}

private void emit_stw(IR* ir, u32 opcode, u32 pc) {
    GuestReg rs = cast(GuestReg) opcode.bits(21, 25);
    GuestReg ra = cast(GuestReg) opcode.bits(16, 20);
    int offset  = opcode.bits(0, 16);

    IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    address = address + sext_32(offset, 16);

    ir.write_u32(address, ir.get_reg(rs));
}

private void emit_mflr(IR* ir, u32 opcode, u32 pc) {
    GuestReg rd = cast(GuestReg) opcode.bits(21, 25);
    int spr     = opcode.bits(11, 20);

    log_jit("SPR: %x", spr);

    assert (
        spr == 0b1000_00000
    );

    GuestReg src;
    // if (spr == 1) src = GuestReg.XER;
    if (spr == 0b100000000) src = GuestReg.LR;
    // if (spr == 8) src = GuestReg.CTR;

    ir.set_reg(rd, ir.get_reg(src));
}

public void emit(IR* ir, u32 opcode, u32 pc) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.ADDI:   emit_addi  (ir, opcode, pc); break;
        case PrimaryOpcode.ADDIS:  emit_addis (ir, opcode, pc); break;
        case PrimaryOpcode.B:      emit_b     (ir, opcode, pc); break;
        case PrimaryOpcode.RLWINM: emit_rlwinm(ir, opcode, pc); break;
        case PrimaryOpcode.MFLR:   emit_mflr  (ir, opcode, pc); break;
        case PrimaryOpcode.STW:    emit_stw   (ir, opcode, pc); break;

        default: error_jit("Unimplemented opcode: %x", opcode);
    }
}
