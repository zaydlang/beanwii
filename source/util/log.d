module util.log;

import emu.scheduler;

__gshared Scheduler* g_logger_scheduler;

enum Whitelist = [
    // LogSource.USB,
    LogSource.BLUETOOTH,
    // LogSource.AI,
    LogSource.BROADWAY,
    // LogSource.DISK,
    // LogSource.DSP,
    // LogSource.FRONTEND,
    // LogSource.INTERRUPT,
    // LogSource.FUNCTION,
    LogSource.IPC,
    // LogSource.JIT,
    // LogSource.HOLLYWOOD,
    // LogSource.OS_REPORT,
    // LogSource.SLOWMEM,
    // LogSource.SCHEDULER,
    LogSource.USB,
    // LogSource.WBFS,
    // LogSource.WII,
];

enum LogSource {
    FUNCTION,
    DISK,
    WBFS,
    ENCRYPTION,
    VMEM,
    BROADWAY,
    SLOWMEM,
    IR,
    JIT,
    XBYAK,
    WII,
    APPLOADER,
    CP,
    VI,
    SI,
    EXI,
    AI,
    IPC,
    INTERRUPT,
    HOLLYWOOD,
    OS_REPORT,
    SCHEDULER,
    PE,
    USB,
    DSP,
    BLUETOOTH,
    DOL,
    FRONTEND
}

static immutable ulong logsource_padding = get_largest_logsource_length!();

static ulong get_largest_logsource_length()(){
    import std.algorithm;
    import std.conv;
    import std.traits;

    ulong largest_logsource_length = 0;
    foreach (source; EnumMembers!LogSource) {
        largest_logsource_length = max(to!string(source).length, largest_logsource_length);
    }

    return largest_logsource_length;
}

// thanks https://github.com/dlang/phobos/blob/4239ed8ebd3525206453784908f5d37c82d338ee/std/outbuffer.d
private void log(LogSource log_source, bool fatal, Char, A...)(scope const(Char)[] fmt, A args) {
    import core.runtime;
    import core.stdc.stdlib;
    import std.array;
    import std.conv;
    import std.format;
    import std.stdio;

    version (silent) {
        return;
    } else {
        version (quiet) {
            if (!fatal) {
                return;
            }
        }

        ulong timestamp = g_logger_scheduler ? g_logger_scheduler.get_current_time_relative_to_cpu() : 0;
        string prefix = format("%016x [%s] : ", timestamp, pad_string_right!(to!string(log_source), logsource_padding));
        string written_string = format(fmt, args);
        written_string = written_string.replace("\n", "\n" ~ prefix);

        if (fatal && g_on_error_callback !is null) {
            g_on_error_callback();
        }


        if (fatal) {
            stderr.writef(prefix);
            stderr.writefln(written_string);
            version (unittest) {
                assert(0);
            } else {
                auto trace = defaultTraceHandler(null);
                foreach (line; trace) {
                    import core.stdc.stdio;
                    printf("%.*s\n", cast(int) line.length, line.ptr);
                }

                exit(-1);
            }
        } else {
            writef(prefix);
            writefln(written_string);
        }
    }
}

alias OnErrorCallback = void function();
__gshared OnErrorCallback g_on_error_callback;

public void set_logger_on_error_callback(OnErrorCallback on_error_callback) {
    g_on_error_callback = on_error_callback;
}

static string pad_string_right(string s, ulong pad)() {
    import std.array;

    static assert(s.length <= pad);
    return s ~ (replicate(" ", pad - s.length));
}

static string generate_prettier_logging_functions() {
    import std.conv;
    import std.format;
    import std.traits;
    import std.uni;

    string mixed_in = "";
    
    foreach (source; EnumMembers!LogSource) {
        string source_name = to!string(source);

        mixed_in ~= "
            public void log_%s(Char, A...)(scope const(Char)[] fmt, A args) {
                import std.algorithm: canFind;
                static if (!Whitelist.canFind(LogSource.%s)) {
                    return;
                }

                version (quiet) {
                } else {
                    log!(LogSource.%s, false, Char, A)(fmt, args);
                }
            }
        ".format(source_name.toLower(), source_name, source_name);

        mixed_in ~= "
            public void error_%s(Char, A...)(scope const(Char)[] fmt, A args) {
                log!(LogSource.%s, true, Char, A)(fmt, args);
            }
        ".format(source_name.toLower(), source_name);

        mixed_in ~= "
            public void assert_%s(Char, A...)(bool condition, scope const(Char)[] fmt, A args) {
                if (!condition) {
                    log!(LogSource.%s, true, Char, A)(fmt, args);
                }
            }
        ".format(source_name.toLower(), source_name);
    }

    return mixed_in;
}

mixin(
    generate_prettier_logging_functions()
);