module test.broadway.jit.allocate_registers;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.passes.allocate_registers.pass;
import emu.hw.broadway.jit.x86;

import std.typecons;

alias RegAssignment = Tuple!(IRVariable, HostReg);


void test_pass(Recipe recipe, RegAssignment[] reg_assignments) {
    foreach (assignment; reg_assignments) {
        recipe.assign_register(assignment[0], assignment[1]);
    }

    auto pass = new AllocateRegisters();
    recipe.pass(pass);

        import std.stdio;
    writeln(recipe.to_string());
}

@("Allocate Registers")
unittest {
    auto v0 = IRVariable(0);
    auto v1 = IRVariable(1);
    auto v2 = IRVariable(2);
    auto v3 = IRVariable(3);
    auto v4 = IRVariable(4);
    auto v5 = IRVariable(5);
    auto v6 = IRVariable(6);
    auto v7 = IRVariable(7);
    auto v8 = IRVariable(8);
    auto v9 = IRVariable(9);
    auto v10 = IRVariable(10);
    auto v11 = IRVariable(11);
    auto v12 = IRVariable(12);
    auto v13 = IRVariable(13);
    auto v14 = IRVariable(14);
    auto v15 = IRVariable(15);
    auto v16 = IRVariable(16);
    auto v17 = IRVariable(17);
    auto v18 = IRVariable(18);
    auto v19 = IRVariable(19);
    auto v20 = IRVariable(20);

    auto ev0 = IRVariable(10000);
    auto ev1 = IRVariable(10001);

    test_pass(
        new Recipe([
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, ev1, v0),
            Instruction.Read(ev0, ev1, 4),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v1, ev0),
        ]),
        [RegAssignment(ev0, HostReg.RAX), 
         RegAssignment(ev1, HostReg.RSI)]
    );

    // use like 20 variables
    test_pass(
        new Recipe([
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v0, v1),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v2, v3),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v4, v5),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v6, v7),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v8, v9),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v10, v11),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v12, v13),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v14, v15),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v16, v17),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v18, v19),
            Instruction.UnaryDataOp(IRUnaryDataOp.MOV, v20, v0),
        ]),
        []
    );
}
