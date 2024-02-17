module emu.hw.broadway.jit.passes.impose_x86_conventions.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.x86;
import std.sumtype;

final class ImposeX86Conventions : RecipePass {
    final class Map : RecipeMap {
        private RecipeAction handle_shift(Recipe recipe, IRInstructionBinaryDataOp instr) {
            return instr.src2.match!(
                (IRVariable v) {
                    IRVariable new_shifter = recipe.fresh_variable();
                    recipe.assign_register(new_shifter, HostReg.RCX);

                    return RecipeAction.Replace(
                        [Instruction.UnaryDataOp(IRUnaryDataOp.MOV, new_shifter, v),
                        Instruction.BinaryDataOp(instr.op, instr.dest, instr.src1, new_shifter)]
                    );
                },
                _ => RecipeAction.DoNothing()
            );
        }

        override public RecipeAction map(Recipe recipe, IRInstruction* instr) {
            return (*instr).match!(
                (IRInstructionBinaryDataOp i) {
                    switch (i.op) {
                        case IRBinaryDataOp.LSL:
                        case IRBinaryDataOp.LSR:
                        case IRBinaryDataOp.ASR:
                        case IRBinaryDataOp.ROL:
                            return handle_shift(recipe, i); 

                        default: return RecipeAction.DoNothing();
                    }
                },

                (IRInstructionRead i) {
                    IRVariable new_dest = recipe.fresh_variable();
                    IRVariable new_address = recipe.fresh_variable();

                    recipe.assign_register(new_dest, HostReg.RAX);
                    recipe.assign_register(new_address, HostReg.RSI);

                    return RecipeAction.Replace(
                        [Instruction.UnaryDataOp(IRUnaryDataOp.MOV, new_address, i.address),
                        Instruction.Read(new_dest, new_address, i.size),
                        Instruction.UnaryDataOp(IRUnaryDataOp.MOV, i.dest, new_dest)]);
                },

                (IRInstructionWrite i) {
                    // two operands, 0 returns
                    IRVariable new_address = recipe.fresh_variable();
                    IRVariable new_dest = recipe.fresh_variable();

                    recipe.assign_register(new_address, HostReg.RSI);
                    recipe.assign_register(new_dest, HostReg.RDX);

                    return RecipeAction.Replace(
                        [Instruction.UnaryDataOp(IRUnaryDataOp.MOV, new_address, i.address),
                        Instruction.UnaryDataOp(IRUnaryDataOp.MOV, new_dest, i.dest),
                        Instruction.Write(new_dest, new_address, i.size)]);
                },

                (IRInstructionReadSized i) {
                    IRVariable new_dest = recipe.fresh_variable();
                    IRVariable new_address = recipe.fresh_variable();
                    IRVariable new_size = recipe.fresh_variable();

                    recipe.assign_register(new_dest, HostReg.RAX);
                    recipe.assign_register(new_address, HostReg.RSI);
                    recipe.assign_register(new_size, HostReg.RDX);

                    return RecipeAction.Replace(
                        [Instruction.UnaryDataOp(IRUnaryDataOp.MOV, new_address, i.address),
                        Instruction.UnaryDataOp(IRUnaryDataOp.MOV, new_size, i.size),
                        Instruction.ReadSized(new_dest, new_address, new_size),
                        Instruction.UnaryDataOp(IRUnaryDataOp.MOV, i.dest, new_dest)]);
                },

                _ => RecipeAction.DoNothing()
            );        
        }
    }

    override public void pass(Recipe recipe) {
        recipe.map(new Map());
    }
}
