module test.broadway.jit.optimize_get_reg;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.passes.optimize_get_reg.pass;

void test_pass(RecipeMap recipe_map, Recipe input, Recipe expected_output) {
    input.map(recipe_map);
    auto actual_output = input;

    if (actual_output != expected_output) {
        import std.stdio;
        writeln("Expected:");
        writeln(expected_output.to_string());
        writeln("Actual:");
        writeln(actual_output.to_string());
        assert(false);
    }
}

@("Optimize get_reg")
unittest {
    auto v0 = IRVariable(null, 0);
    auto v1 = IRVariable(null, 1);

    test_pass(new OptimizeGetReg(),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R0),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v1, v0)
        ])
    );
}