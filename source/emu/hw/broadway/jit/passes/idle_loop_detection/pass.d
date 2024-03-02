module emu.hw.broadway.jit.passes.idle_loop_detection.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.jit;
import emu.hw.broadway.jit.x86;
import std.sumtype;

final class IdleLoopDetection : RecipePass {
    private JitContext jit_context;

    // TODO: move this shit to pass
    public void init(JitContext ctx) {
        this.jit_context = ctx;
    }

    override public void pass(Recipe recipe) {
        if (recipe.length() > 1) {
            return;
        }

        (*recipe[0]).match!(
            (IRInstructionSetReg i) {
                i.src.match!(
                    (int pc) {
                        if (pc == jit_context.pc) {
                            recipe.replace(recipe[0], [Instruction.HaltCpu()]);
                        }
                    },

                    (_) {}
                );
            },

            (_) {}
        );
    }
}
