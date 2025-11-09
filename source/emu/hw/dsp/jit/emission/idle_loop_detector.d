module emu.hw.dsp.jit.emission.idle_loop_detector;

import emu.hw.dsp.jit.emission.decoder;
import util.bitop;
import util.number;
import util.log;
import std.stdio;

private u16 get_dest_reg_for_mailbox_load_instruction(DspInstruction instruction) {
    switch (instruction.opcode) {
        case DspOpcode.LR:
            return instruction.lr.r;
        
        case DspOpcode.LRS:
            return cast(u16) (24 + instruction.lrs.r);
        
        default:
            return 0;
    }
}

private bool is_instruction_mailbox_load(DspInstruction instruction) {
    switch (instruction.opcode) {
        case DspOpcode.LR:
            return instruction.lr.m == 0xFC || instruction.lr.m == 0xFE;
        
        case DspOpcode.LRS:
            return instruction.lrs.m == 0xFC || instruction.lrs.m == 0xFE;
        
        default:
            return false;
    }
}

private u16 get_test_reg_for_and_instruction(DspInstruction instruction) {
    switch (instruction.opcode) {
        case DspOpcode.ANDCF:
            return cast(u16) (30 + instruction.andcf.r);
        
        case DspOpcode.ANDF:
            return cast(u16) (30 + instruction.andf.r);
        
        default:
            return 0;
    }
}

private bool is_instruction_and_with_mail_bit(DspInstruction instruction) {
    switch (instruction.opcode) {
        case DspOpcode.ANDCF:
            return instruction.andcf.i == 0x8000;
        
        case DspOpcode.ANDF:
            return instruction.andf.i == 0x8000;
        
        default:
            return false;
    }
}

private bool is_instruction_conditional_jump_back(DspInstruction instruction, u16 target_pc) {
    return instruction.opcode == DspOpcode.JMP_CC && instruction.jmp_cc.a == target_pc;
}

final class DspIdleLoopDetector {
    private DspInstruction[3] first_three_instructions;
    private size_t num_instructions_added;
    private u16 block_start_pc;

    this() {
    }

    void reset(u16 pc) {
        num_instructions_added = 0;
        block_start_pc = pc;
    }

    void add(DspInstruction instruction) {
        if (num_instructions_added < 3) {
            first_three_instructions[num_instructions_added] = instruction;
        }

        num_instructions_added++;
    }

    bool is_in_idle_loop() {
        if (num_instructions_added == 3 &&
            is_instruction_mailbox_load(first_three_instructions[0]) &&
            is_instruction_and_with_mail_bit(first_three_instructions[1]) &&
            is_instruction_conditional_jump_back(first_three_instructions[2], block_start_pc) &&
            get_dest_reg_for_mailbox_load_instruction(first_three_instructions[0]) == get_test_reg_for_and_instruction(first_three_instructions[1])) {
            
            return true;
        }

        return false;
    }
}