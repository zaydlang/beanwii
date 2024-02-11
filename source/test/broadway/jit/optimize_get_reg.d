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
    auto v0 = IRVariable(0);
    auto v1 = IRVariable(1);
    auto v2 = IRVariable(2);

    test_pass(new OptimizeGetReg(),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.GetReg(v1, GuestReg.R0),
        ]),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v1, v0)
        ])
    );

    test_pass(new OptimizeGetReg(),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.GetReg(v1, GuestReg.R1),
            Instruction.GetReg(v0, GuestReg.R0),
        ]),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.GetReg(v1, GuestReg.R1),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v0, v0)
        ])
    );

    // no opt
    test_pass(new OptimizeGetReg(),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.GetReg(v1, GuestReg.R1),
            Instruction.GetReg(v2, GuestReg.R2),
        ]),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.GetReg(v1, GuestReg.R1),
            Instruction.GetReg(v2, GuestReg.R2),
        ])
    );

    // set reg influces movement
    test_pass(new OptimizeGetReg(),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.GetReg(v1, GuestReg.R0),
        ]),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v1, v0),
        ])
    );

    // more complex set reg
    test_pass(new OptimizeGetReg(),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.SetReg(GuestReg.R1, v1),
            Instruction.GetReg(v2, GuestReg.R0),
        ]),
        new Recipe([
            Instruction.SetReg(GuestReg.R0, v0),
            Instruction.SetReg(GuestReg.R1, v1),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v2, v0),
        ])
    );
   
   // even more complex get reg
    test_pass(new OptimizeGetReg(),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.GetReg(v1, GuestReg.R0),
            Instruction.GetReg(v2, GuestReg.R0),
        ]),
        new Recipe([
            Instruction.GetReg(v0, GuestReg.R0),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v1, v0),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v2, v1),
        ])
    );
}