module emu.hw.broadway.jit.emission.idle_loop_detector;

import emu.hw.broadway.jit.emission.guest_reg;
import emu.hw.broadway.jit.emission.opcode;
import emu.hw.memory.strategy.memstrategy;
import std.stdio;
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

private bool is_instruction_branch_with_link(u32 opcode) {
    return opcode.bits(26, 31) == PrimaryOpcode.B && opcode.bits(0, 1) == 1;
}

private int get_destination_offset_for_branch_with_link_instruction(u32 opcode) {
    return sext_32(opcode.bits(2, 25), 24) << 2;
}

private bool is_instruction_compare_logical_immediate(u32 opcode) {
    return opcode.bits(26, 31) == PrimaryOpcode.CMPLI;
}

private int get_comparator_reg_idx_for_compare_logical_immediate(u32 opcode) {
    return opcode.bits(16, 20);
}

private u16 get_immediate_value_for_compare_logical_immediate(u32 opcode) {
    return cast(u16) opcode.bits(0, 15);
}

// at this point i no longer give a shit
private bool is_mmio_polling_function(u32 pc_address, Mem memory) {
    u32 instruction1 = memory.cpu_read_u32(pc_address);
    u32 instruction2 = memory.cpu_read_u32(pc_address + 4);
    u32 instruction3 = memory.cpu_read_u32(pc_address + 8);
    u32 instruction4 = memory.cpu_read_u32(pc_address + 12);
    
    return instruction1 == 0x3c60cc00 &&
           instruction2 == 0xa0035000 &&
           instruction3 == 0x54038ffe &&
           instruction4 == 0x4e800020;
}

enum IdleLoopType {
    MemoryPolling,
    DSPMailboxRead
}

final class IdleLoopDetector {
    private u32[3] first_three_instructions;
    private size_t num_instructions_added;
    private u32 block_start_pc;
    private Mem memory;
    private IdleLoopType detected_type;
    public  bool debug_prints;

    this(Mem memory) {
        first_three_instructions = [0, 0, 0];
        this.memory = memory;
    }

    void reset(u32 pc) {
        num_instructions_added = 0;
        block_start_pc = pc;
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

            detected_type = IdleLoopType.MemoryPolling;
            return true;
        }

        if (num_instructions_added == 2 &&
            is_instruction_compare_logical_immediate(first_three_instructions[0]) &&
            is_instruction_conditional_branch(first_three_instructions[1]) &&
            get_destination_offset_for_conditional_branch_instruction(first_three_instructions[1]) == -8 &&
            get_comparator_reg_idx_for_compare_logical_immediate(first_three_instructions[0]) == 3 &&
            get_immediate_value_for_compare_logical_immediate(first_three_instructions[0]) == 0) {
            
            u32 prev_instr = memory.cpu_read_u32(block_start_pc - 4);
            if (is_instruction_branch_with_link(prev_instr)) {
                u32 bl_pc = block_start_pc - 4;
                u32 bl_target = bl_pc + get_destination_offset_for_branch_with_link_instruction(prev_instr);
                if (is_mmio_polling_function(bl_target, memory)) {
                    writefln("Found MMIO function call idle loop at PC=0x%08X", bl_pc);
                    detected_type = IdleLoopType.DSPMailboxRead;
                    return true;
                }
            }
        }
        
        if (block_start_pc == 0x80496358) {
            writefln("Debug 0x80496358: num_instructions=%d", num_instructions_added);
            if (num_instructions_added >= 1) {
                writefln("  instr[0]=0x%08X is_bl=%s", first_three_instructions[0], is_instruction_branch_with_link(first_three_instructions[0]));
            }
            if (num_instructions_added >= 2) {
                writefln("  instr[1]=0x%08X is_cmplwi=%s reg=%d imm=%d", first_three_instructions[1], 
                    is_instruction_compare_logical_immediate(first_three_instructions[1]),
                    get_comparator_reg_idx_for_compare_logical_immediate(first_three_instructions[1]),
                    get_immediate_value_for_compare_logical_immediate(first_three_instructions[1]));
            }
            if (num_instructions_added >= 3) {
                writefln("  instr[2]=0x%08X is_bc=%s offset=%d", first_three_instructions[2],
                    is_instruction_conditional_branch(first_three_instructions[2]),
                    get_destination_offset_for_conditional_branch_instruction(first_three_instructions[2]));
                if (is_instruction_branch_with_link(first_three_instructions[0])) {
                    u32 bl_target = block_start_pc + get_destination_offset_for_branch_with_link_instruction(first_three_instructions[0]);
                    writefln("  bl_target=0x%08X is_mmio_func=%s", bl_target, is_mmio_polling_function(bl_target, memory));
                    if (!is_mmio_polling_function(bl_target, memory)) {
                        u32 instruction1 = memory.cpu_read_u32(bl_target);
                        u32 instruction2 = memory.cpu_read_u32(bl_target + 4);
                        u32 instruction3 = memory.cpu_read_u32(bl_target + 8);
                        u32 instruction4 = memory.cpu_read_u32(bl_target + 12);
                        writefln("    target[0]=0x%08X (expected 0x3c60cc00)", instruction1);
                        writefln("    target[1]=0x%08X (expected 0xa0035000)", instruction2);
                        writefln("    target[2]=0x%08X (expected 0x54038ffe)", instruction3);
                        writefln("    target[3]=0x%08X (expected 0x4e800020)", instruction4);
                    }
                }
            }
        }

        return false;
    }

    bool has_memory_accessor_reg() {
        return detected_type == IdleLoopType.MemoryPolling;
    }

    GuestReg get_memory_accessor_reg() {
        return get_dest_reg_idx_for_memory_read_instruction(first_three_instructions[0]).to_gpr;
    }
    
    IdleLoopType get_idle_loop_type() {
        return detected_type;
    }
}