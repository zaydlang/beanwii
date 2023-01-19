module test.broadway.framework;

import emu.hw.broadway.cpu;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.memory.strategy;
import util.number;

struct TestState {
    private bool     test_initted = false;
    private Broadway broadway;
    private Mem      mem;
}

private __gshared TestState test_state;

private enum BROADWAY_CPU_START_PC = 0x8000_0000;

public void test_init() {
    test_state.broadway = new Broadway(0);
    test_state.mem      = new Mem();
    test_state.broadway.connect_mem(test_state.mem);
    test_state.test_initted = true;
}

public TestState* test(BroadwayState* broadway_state, u32[] opcodes) {
    TestState* test_state = new TestState();

    for (int i = 0; i < opcodes.length; i++) {
        mem.write_be_u32(opcodes[i], BROADWAY_CPU_START_PC + i);
    }
    mem.write_be_u32(0x4e800020); // blr

    broadway_state.pc = BROADWAY_CPU_START_PC;
    return test_state;
}

public TestState* run(TestState* test_state) {
    broadway.run_until_return();
}

void expect(T)(BroadwayState broadway_state, GuestReg guest_reg, T value) {
    import std.traits;
    
    final switch (guest_reg) {
        foreach (case_reg; EnumMembers!GuestReg) {
            case case_reg: mixin("assert(broadway_state." ~ case_reg ~ " == value);");
        }
    }
}
