module emu.hw.broadway.cpu;

import capstone;
import emu.hw.broadway.state;
import emu.hw.memory.strategy.memstrategy;
import util.endian;
import util.log;
import util.number;

final class BroadwayCpu {
    private Mem           mem;
    private BroadwayState state;

    this(Mem mem) {
        this.mem = mem;
    }

    public void set_pc(u32 pc) {
        state.pc = pc;
    }

    public void run_instruction() {
        for (int i = 0; i < 5; i++) {
            u32 instruction = cast(u32) fetch();
            // log_broadway("Instruction: %x", instruction);
            auto cs = create(Arch.ppc, ModeFlags(Mode.bit64));
            auto res = cs.disasm((cast(ubyte*) &instruction)[0 .. 4], 4);
            foreach(instr; res)
                log_broadway("0x%x:\t%s\t\t%s", instr.address, instr.mnemonic, instr.opStr);
        }
    }

    private u32_be fetch() {
        u32_be instruction = mem.read_be_u32(state.pc);
        state.pc += 4;
        return instruction;
    }
}