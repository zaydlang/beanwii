module test.broadway.paired_single;

import test.broadway.framework;

private void test_PSQ_L() {
    broadway_test([
        0xE0000008 // PSQ_L F0, 0(R0)
    ])
    .set_gqr(0, 0x00040000) // LD_TYPE = Unsigned 8 bit, LD_SCALE = 0
    .set_gpr(0, 0x90000000)
    .write_u8(0x90000000, 0x32)
    .write_u8(0x90000001, 0xA7)
    .run()
    .expect_ps(0, 0, 0);
}

 @("PSQ_L")
unittest { 
    test_PSQ_L(); 
}