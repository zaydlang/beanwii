module emu.hw.broadway.jit.emission.floating_point;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.guest_reg;
import util.bitop;
import util.log;
import util.number;
import xbyak;

EmissionAction emit_fmr(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

EmissionAction emit_lfd(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

EmissionAction emit_mftsb1(Code code, u32 opcode) {
    bool rc = opcode.bit(0);

    // TODO: ist his supposed to be backwards indexed?
    int crbD = opcode.bits(21, 25);

    // what?
    assert(!rc);

    assert(opcode.bits(11, 20) == 0);

    code.or(code.get_address(GuestReg.FPSCR), 1 << crbD);

    return EmissionAction.CONTINUE;
}
