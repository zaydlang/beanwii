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
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R0),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v1, v0)
        ])
    );

    test_pass(new OptimizeGetReg(),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R1),
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R1),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v0, v0)
        ])
    );

    // double move
    test_pass(new OptimizeGetReg(),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v2, GuestReg.R0),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v1, v0),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v2, v0),
        ])
    );

    // no opt
    test_pass(new OptimizeGetReg(),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R1),
            cast(IRInstruction) IRInstructionGetReg(v2, GuestReg.R2),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionGetReg(v0, GuestReg.R0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R1),
            cast(IRInstruction) IRInstructionGetReg(v2, GuestReg.R2),
        ])
    );

    // set reg influces movement
    test_pass(new OptimizeGetReg(),
        new Recipe([
            cast(IRInstruction) IRInstructionSetRegVar(GuestReg.R0, v0),
            cast(IRInstruction) IRInstructionGetReg(v1, GuestReg.R0),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionSetRegVar(GuestReg.R0, v0),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v1, v0),
        ])
    );

    // more complex set reg
    test_pass(new OptimizeGetReg(),
        new Recipe([
            cast(IRInstruction) IRInstructionSetRegVar(GuestReg.R0, v0),
            cast(IRInstruction) IRInstructionSetRegVar(GuestReg.R1, v1),
            cast(IRInstruction) IRInstructionGetReg(v2, GuestReg.R0),
        ]),
        new Recipe([
            cast(IRInstruction) IRInstructionSetRegVar(GuestReg.R0, v0),
            cast(IRInstruction) IRInstructionSetRegVar(GuestReg.R1, v1),
            cast(IRInstruction) IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, v2, v0),
        ])
    );
}