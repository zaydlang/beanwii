module emu.hw.broadway.jit.frontend.opcode;

enum PrimaryOpcode {
    ADDI   = 0xE,
    ADDIS  = 0xF,
    B      = 0x12,
    RLWINM = 0x15,
    MFLR   = 0x1F,
    LWZ    = 0x20,
    STW    = 0x24
}
