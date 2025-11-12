module emu.hw.broadway.exception_type;

enum ExceptionType {
    SystemReset,
    MachineCheck,
    FloatingPointUnavailable,
    DataStorage,
    InstructionStorage,
    ExternalInterrupt,
    Alignment,
    Program,
    Decrementer,
    SystemCall,
    Trace,
    PerformanceMonitor
}
