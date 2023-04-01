module emu.hw.broadway.interrupt;

import util.bitop;
import util.log;
import util.number;

enum InterruptCause {
    GP_RUNTIME_ERROR = 0,
    RESET_SWITCH     = 1,
    DVD              = 2,
    SERIAL           = 3,
    EXI              = 4,
    AI               = 5,
    DSP              = 6,
    MEM              = 7,
    VI               = 8,
    PE_TOKEN         = 9,
    PE_FINISH        = 10,
    CP_FIFO          = 11,
    DEBUGGER         = 12,
    HIGHSPEED_PORT   = 13,
    HOLLYWOOD        = 14,
}

final class InterruptController {
    u32 interrupt_mask;

    u8 read_INTERRUPT_MASK(int target_byte) {
        return interrupt_mask.get_byte(target_byte);
    }

    void write_INTERRUPT_MASK(int target_byte, u8 value) {
        interrupt_mask = interrupt_mask.set_byte(target_byte, value);
    }
}