module test.broadway.jit.optimize_set_reg;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.passes.optimize_set_reg.pass;

void test_pass(RecipeMap recipe_map, Recipe input, Recipe expected_output) {
    input.reverse_map(recipe_map);
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

@("Optimize set_reg")
unittest {
    auto v0 = IRVariable(0);
    auto v1 = IRVariable(1);
    auto v2 = IRVariable(2);

    test_pass(new OptimizeSetReg(),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.SetReg(GuestReg.R0, v1),
        ]),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v1),
        ])
    );

    test_pass(new OptimizeSetReg(),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.SetReg(GuestReg.R1, v1),
            Instruction.SetReg(GuestReg.R0, v2),
        ]),
        new Recipe([
            Instruction.SetReg(GuestReg.R1, v1),
            Instruction.SetReg(GuestReg.R0, v2),
        ])
    );

    test_pass(new OptimizeSetReg(),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.SetReg(GuestReg.R1, v1),
            Instruction.SetReg(GuestReg.R0, v2),
            Instruction.SetReg(GuestReg.R1, v2),
        ]),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v2),
            Instruction.SetReg(GuestReg.R1, v2),
        ])
    );
}