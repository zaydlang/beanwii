module util.log;

enum LogSource {
    DISK,
    WBFS,
    ENCRYPTION,
    VMEM,
    BROADWAY,
    SLOWMEM
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
    import core.stdc.stdio;
    import core.stdc.stdlib;
    import std.conv;
    import std.format;
    import std.stdio;

    version (silent) {
        return;
    } else {
        ulong timestamp = 0; // scheduler.get_current_time_relative_to_cpu();
        writef("%016x [%s] : ", timestamp, pad_string_right!(to!string(log_source), logsource_padding));
        writefln(fmt, args);

        if (fatal) {
            auto trace = defaultTraceHandler(null);
            foreach (line; trace) {
                printf("%.*s\n", cast(int) line.length, line.ptr);
            }

            exit(-1);
        }
    }
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
                version (quiet) {
                } else {
                    log!(LogSource.%s, false, Char, A)(fmt, args);
                }
            }
        ".format(source_name.toLower(), source_name);

        mixed_in ~= "
            public void error_%s(Char, A...)(scope const(Char)[] fmt, A args) {
                log!(LogSource.%s, true, Char, A)(fmt, args);
            }
        ".format(source_name.toLower(), source_name);
    }

    return mixed_in;
}

mixin(
    generate_prettier_logging_functions()
);