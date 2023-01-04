module emu.hw.broadway.jit.frontend.opcode;

enum PrimaryOpcode {
    ADDI   = 0xE,
    ADDIS  = 0xF,
    RLWINM = 0x15,
    STW    = 0x24
}
