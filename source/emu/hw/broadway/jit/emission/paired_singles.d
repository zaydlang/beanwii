module emu.hw.broadway.jit.emission.paired_singles;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.emit;
import emu.hw.broadway.jit.emission.guest_reg;
import util.log;
import util.number;
import xbyak;

// fuck this instruction omg
EmissionAction emit_psq_l(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}

EmissionAction emit_ps_mr(Code code, u32 opcode) {
    return EmissionAction.CONTINUE;
}
