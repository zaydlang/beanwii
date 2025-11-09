module util.signal;

import util.log;

version(Posix) {
    import core.sys.posix.signal;
    import core.sys.posix.ucontext;
    import core.stdc.stdio;
    import core.stdc.stdlib;
}

alias SegfaultCallback = void function();
__gshared SegfaultCallback g_segfault_callback;

public void set_segfault_callback(SegfaultCallback callback) {
    g_segfault_callback = callback;
}

version(Posix) {
    extern(C) void segfault_handler(int signum, siginfo_t* info, void* context) {
        log_util("Segmentation fault caught at address: 0x%x", info.si_addr);
        
        if (g_segfault_callback !is null) {
            log_util("Calling error handler...");
            g_segfault_callback();
        }
        
        // Print a stack trace if possible
        version(unittest) {
            assert(0);
        } else {
            import core.runtime;
            auto trace = defaultTraceHandler(null);
            log_util("Stack trace:");
            foreach (line; trace) {
                printf("%.*s\n", cast(int) line.length, line.ptr);
            }
        }
        
        error_util("Segmentation fault at address 0x%x - terminating", info.si_addr);
    }
}

public void install_segfault_handler() {
    version(Posix) {
        sigaction_t sa;
        sa.sa_flags = SA_SIGINFO;
        sa.sa_sigaction = &segfault_handler;
        sigemptyset(&sa.sa_mask);
        
        if (sigaction(SIGSEGV, &sa, null) == -1) {
            error_util("Failed to install segfault handler");
        } else {
            log_util("Segfault handler installed successfully");
        }
    } else {
        log_util("Segfault handler not supported on non-POSIX systems");
    }
}