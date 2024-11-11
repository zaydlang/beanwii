module emu.hw.broadway.exception_type;

enum ExceptionType {
    SystemReset,
    MachineCheck,
    DataStorage,
    InstructionStorage,
    ExternalInterrupt,
    Alignment,
    Program,
    FloatingPointUnavailable,
    Decrementer,
    SystemCall,
    Trace,
    PerformanceMonitor
}
