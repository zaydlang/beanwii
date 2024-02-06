module emu.hw.broadway.jit.passes.optimize_get_reg.pass;

import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;

final class OptimizeGetReg : RecipeMap {
    override public RecipeAction func(IRInstruction instr) {
        return cast(RecipeAction) RecipeActionDoNothing();
    }
}
