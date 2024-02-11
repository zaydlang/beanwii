module emu.hw.broadway.jit.passes.optimize_get_reg.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import std.sumtype;

final class OptimizeGetReg : RecipeMap {
    IROperand[GuestReg] reg_map;

    override public RecipeAction func(IRInstruction* instr) {
        return (*instr).match!(
            (IRInstructionGetReg i) {
                if (!i.src.is_read_volatile()) {
                    if (i.src in reg_map) {
                        auto replaced_src = reg_map[i.src];
                        reg_map[i.src] = i.dest;

                        return RecipeAction.Replace(instr,
                            [Instruction.UnaryDataOp(IRUnaryDataOp.MOV, i.dest, replaced_src)]);
                    }

                    reg_map[i.src] = i.dest;
                }

                return RecipeAction.DoNothing();
            },

            (IRInstructionSetReg i) {
                reg_map[i.dest] = i.src;
                return RecipeAction.DoNothing();
            },

            _ => RecipeAction.DoNothing()
        );        
    }
}
