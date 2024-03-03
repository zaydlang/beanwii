module emu.hw.broadway.jit.passes.mov_simplification.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.x86;
import std.sumtype;

final class MovSimplification : RecipePass {
    final class Map : RecipeMap {
        IRVariable[IRVariable] copy_map;

        private IRVariable map_var(IRVariable var) {
            if (var in copy_map) {
                return copy_map[var];
            } else {
                return var;
            }
        }

        override public RecipeAction map(Recipe recipe, IRInstruction* instr) {
            return (*instr).match!(
                (IRInstructionUnaryDataOp i) {
                    if (i.op == IRUnaryDataOp.MOV) {
                        return i.src.match!(
                            (IRVariable v) {
                                copy_map[i.dest] = map_var(v);
                                return RecipeAction.Remove();
                            },

                            (_) => RecipeAction.DoNothing()
                        );
                    } else {
                        return RecipeAction.Replace([(*instr).map_across_variables(&map_var)]);
                    }

                },

                (_) => RecipeAction.Replace([(*instr).map_across_variables(&map_var)])
            );
        }
    }

    private Map map;

    this() {
        this.map = new Map();
    }

    override public void pass(Recipe recipe) {
        recipe.map(this.map);
    }
}
