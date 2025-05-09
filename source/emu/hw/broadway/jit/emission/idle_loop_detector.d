module emu.hw.broadway.jit.emission.idle_loop_detector;

import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.opcode;
import util.bitop;
import util.number;
import util.log;

private int get_dest_reg_idx_for_memory_read_instruction(u32 opcode) {
    return opcode.bits(21, 25);
}

private bool is_instruction_single_memory_read(u32 opcode) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.LBZ:
        case PrimaryOpcode.LFD:
        case PrimaryOpcode.LFS:
        case PrimaryOpcode.LHA:
        case PrimaryOpcode.LHZ:
        case PrimaryOpcode.LWZ:
            return true;

        case PrimaryOpcode.OP_1F:
            switch (opcode.bits(1, 10)) {
                case PrimaryOp1FSecondaryOpcode.LBZX:
                case PrimaryOp1FSecondaryOpcode.LFDX:
                case PrimaryOp1FSecondaryOpcode.LFSX:
                case PrimaryOp1FSecondaryOpcode.LHAX:
                case PrimaryOp1FSecondaryOpcode.LHZX:
                case PrimaryOp1FSecondaryOpcode.LWZX:
                    return true;
                
                default: 
                    return false;
            }

        default:
            return false;
    }
}

private int get_comparator_reg_idx_for_compare_instruction(u32 opcode) {
    return opcode.bits(16, 20);
}

private bool is_instruction_compare_against_immediate(u32 opcode) {
    int primary_opcode = opcode.bits(26, 31);

    switch (primary_opcode) {
        case PrimaryOpcode.CMPI:
        case PrimaryOpcode.CMPLI:
            return true;

        default:
            return false;
    }
}

private bool is_instruction_pc_relative_unconditional_branch_without_link(u32 opcode) {
    return opcode.bits(26, 31) == PrimaryOpcode.B && opcode.bits(0, 1) == 0;
}

private bool is_instruction_conditional_branch(u32 opcode) {
    return opcode.bits(26, 31) == PrimaryOpcode.BC;
}

private int get_destination_offset_for_unconditional_branch_instruction(u32 opcode) {
    return sext_32(opcode.bits(2, 25), 24) << 2;
}

private int get_destination_offset_for_conditional_branch_instruction(u32 opcode) {
    return sext_32(opcode.bits(2, 15), 14) << 2;
}

final class IdleLoopDetector {
    private u32[3] first_three_instructions;
    private size_t num_instructions_added;
    public  bool debug_prints;

    this() {
        first_three_instructions = [0, 0, 0];
    }

    void reset() {
        num_instructions_added = 0;
    }

    void add(u32 instruction) {
        if (num_instructions_added < 3) {
            first_three_instructions[num_instructions_added] = instruction;
        }

        num_instructions_added++;
    }

    bool is_in_idle_loop() {
        if (num_instructions_added == 1 &&
            is_instruction_pc_relative_unconditional_branch_without_link(first_three_instructions[0]) &&
            get_destination_offset_for_unconditional_branch_instruction(first_three_instructions[0]) == 0) {
            
            return true;
        }

        if (num_instructions_added == 3 &&
            is_instruction_single_memory_read(first_three_instructions[0]) &&
            is_instruction_compare_against_immediate(first_three_instructions[1]) &&
            is_instruction_conditional_branch(first_three_instructions[2]) &&
            get_destination_offset_for_conditional_branch_instruction(first_three_instructions[2]) == -8 &&
            get_dest_reg_idx_for_memory_read_instruction(first_three_instructions[0]) == get_comparator_reg_idx_for_compare_instruction(first_three_instructions[1])) {

            return true;
        }

        return false;
    }

    bool has_memory_accessor_reg() {
        return num_instructions_added == 3;
    }

    GuestReg get_memory_accessor_reg() {
        return get_dest_reg_idx_for_memory_read_instruction(first_three_instructions[0]).to_gpr;
    }
}