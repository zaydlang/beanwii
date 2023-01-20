module test.broadway.framework;

import emu.hw.broadway.cpu;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.memory.strategy.memstrategy;
import util.number;

struct TestState {
    private Broadway broadway;
    private Mem      mem;
}

private __gshared TestState g_test_state;

private enum BROADWAY_CPU_START_PC = 0x8000_0000;

public TestState* broadway_test(u32[] opcodes) {
    TestState* test_state = new TestState();
    test_state.broadway   = new Broadway(0);
    test_state.mem        = new Mem();
    test_state.broadway.connect_mem(test_state.mem);

    u32 current_address = BROADWAY_CPU_START_PC;
    for (int i = 0; i < opcodes.length; i++) {
        test_state.mem.write_be_u32(current_address, opcodes[i]);
        current_address += 4;
    }
    test_state.mem.write_be_u32(current_address, 0x4e800020); // blr

    test_state.broadway.set_pc(BROADWAY_CPU_START_PC);
    return test_state;
}

public TestState* run(TestState* test_state) {
    test_state.broadway.run_until_return();
    return test_state;
}

public TestState* write_u64(TestState* test_state, u32 address, u64 value) {
    test_state.mem.write_be_u64(address, value);
    return test_state;
}

public TestState* write_u32(TestState* test_state, u32 address, u32 value) {
    test_state.mem.write_be_u64(address, value);
    return test_state;
}

public TestState* write_u16(TestState* test_state, u32 address, u16 value) {
    test_state.mem.write_be_u64(address, value);
    return test_state;
}

public TestState* write_u8(TestState* test_state, u32 address, u8 value) {
    test_state.mem.write_be_u64(address, value);
    return test_state;
}

public TestState* set_gpr(TestState* test_state, u32 gpr, u32    value) { test_state.broadway.set_gpr(gpr, value); return test_state; }
public TestState* set_fpr(TestState* test_state, u32 fpr, double value) { test_state.broadway.set_fpr(fpr, value); return test_state; }
public TestState* set_gqr(TestState* test_state, u32 gqr, u32    value) { test_state.broadway.set_gqr(gqr, value); return test_state; }
public TestState* set_cr (TestState* test_state, int cr,  u32    value) { test_state.broadway.set_cr (cr,  value); return test_state; }
public TestState* set_xer(TestState* test_state,          u32    value) { test_state.broadway.set_xer(value);      return test_state; }
public TestState* set_ctr(TestState* test_state,          u32    value) { test_state.broadway.set_ctr(value);      return test_state; }
public TestState* set_lr (TestState* test_state,          u32    value) { test_state.broadway.set_lr (value);      return test_state; }
public TestState* set_pc (TestState* test_state,          u32    value) { test_state.broadway.set_pc (value);      return test_state; }
public TestState* expect_gpr(TestState* test_state, u32 gpr, u32    value) { assert(test_state.broadway.get_gpr(gpr) == value); return test_state; }
public TestState* expect_fpr(TestState* test_state, u32 fpr, double value) { assert(test_state.broadway.get_fpr(fpr) == value); return test_state; }
public TestState* expect_gqr(TestState* test_state, u32 gqr, u32    value) { assert(test_state.broadway.get_gqr(gqr) == value); return test_state; }
public TestState* expect_cr (TestState* test_state, int cr,  u32    value) { assert(test_state.broadway.get_cr (cr)  == value); return test_state; }
public TestState* expect_xer(TestState* test_state,          u32    value) { assert(test_state.broadway.get_xer()    == value); return test_state; }
public TestState* expect_ctr(TestState* test_state,          u32    value) { assert(test_state.broadway.get_ctr()    == value); return test_state; }
public TestState* expect_lr (TestState* test_state,          u32    value) { assert(test_state.broadway.get_lr ()    == value); return test_state; }
public TestState* expect_pc (TestState* test_state,          u32    value) { assert(test_state.broadway.get_pc ()    == value); return test_state; }

public TestState* set_ps    (TestState* test_state, int ps,  float val0, float val1) {
    double fpr = test_state.broadway.get_fpr(ps);
    float* fpr_as_float = cast(float*) &fpr;
    fpr_as_float[0] = val0;
    fpr_as_float[1] = val1;
    set_fpr(test_state, ps, fpr);
    return test_state;
}

public TestState* expect_ps (TestState* test_state, int ps,  float val0, float val1) {
    double fpr = test_state.broadway.get_fpr(ps);
    float* fpr_as_float = cast(float*) &fpr;
    assert(fpr_as_float[0] == val0);
    assert(fpr_as_float[1] == val1);
    return test_state;
}