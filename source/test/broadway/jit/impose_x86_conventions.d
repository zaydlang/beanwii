module test.broadway.jit.impose_x86_conventions;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.passes.impose_x86_conventions.pass;
import emu.hw.broadway.jit.x86;

import std.typecons;

alias RegAssignment = Tuple!(IRVariable, HostReg);

void test_pass(RecipeMap recipe_map, Recipe input, Recipe expected_output, RegAssignment[] expected_reg_assignments) {
    input.map(recipe_map);
    auto actual_output = input;

    foreach (assignment; expected_reg_assignments) {
        expected_output.assign_register(assignment[0], assignment[1]);
    }

    if (actual_output != expected_output) {
        import std.stdio;
        writeln("Expected:");
        writeln(expected_output.to_string());
        writeln("Actual:");
        writeln(actual_output.to_string());
        assert(false);
    }
}

@("Impose X86 Conventions")
unittest {
    auto v0 = IRVariable(0);
    auto v1 = IRVariable(1);
    auto ev0 = IRVariable(10000);
    auto ev1 = IRVariable(10001);

    test_pass(new ImposeX86Conventions(),
        new Recipe([
            Instruction.Read(v1, v0, 4),
        ]),
        new Recipe([
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, ev1, v0),
            Instruction.Read(ev0, ev1, 4),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v1, ev0),
        ]),
        [RegAssignment(ev0, HostReg.RAX), 
         RegAssignment(ev1, HostReg.RSI)]
    );

    // write
    test_pass(new ImposeX86Conventions(),
        new Recipe([
            Instruction.Write(v0, v1, 4),
        ]),
        new Recipe([
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, ev0, v1),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, ev1, v0),
            Instruction.Write(ev1, ev0, 4),
        ]),
        [RegAssignment(ev1, HostReg.RDX),
         RegAssignment(ev0, HostReg.RSI)]
    );
}