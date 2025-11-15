module emu.hw.broadway.gdb;

import core.stdc.stdlib; 
import core.sys.posix.signal;
import emu.hw.broadway.cpu;
import emu.hw.memory.strategy.memstrategy;
import std.algorithm;
import std.array;
import std.conv;
import std.socket;
import std.stdio;
import util.log;
import util.number;

__gshared GDBStub gdb_stub;

extern(C)
void sigint_handler(int signum, siginfo_t* info, void* context) {
    if (gdb_stub !is null) {
        gdb_stub.sigint();
    }
}

final class GDBStub {
    private bool interrupted;

    struct Command {
        string shortname;
        string name;
        string description;
        bool delegate(string handler) handler;
    }

    Command[] commands;

    Broadway cpu;
    Mem mem;

    bool was_breakpoint_hit;
    bool needs_to_hang_at_start;

    this() {
        sigaction_t sa;
        sa.sa_flags = SA_SIGINFO;
        sa.sa_sigaction = &sigint_handler;
        sigaction(SIGINT, &sa, null);

        this.interrupted = false;
        gdb_stub = this;

        commands = [
            Command("h", "help",     "Show help",            &show_help),
            Command("c", "continue", "Continue execution",   &continue_execution),
            Command("b", "break",    "Set a breakpoint",     &create_breakpoint),
            Command("g", "gprs",     "Show gprs / pc / lr",  &show_gprs),
            Command("r", "read",     "Read memory",          &read_memory),
            Command("w", "write",    "Write memory",         &write_memory),
            Command("l", "log",      "Log memory writes",    &log_memory_writes),
            Command("s", "step",     "Step one instruction", &step_instruction),
            Command("t", "stack",    "Show stack",           &show_stack),
            Command("q", "quit",     "Quit beanwii",         &quit_gdb),
        ];
    }

    void connect_broadway(Broadway cpu) {
        this.cpu = cpu;
    }

    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    bool needs_handling() {
        return interrupted || was_breakpoint_hit || needs_to_hang_at_start;
    }

    void enter() {
        enter_gdb_run_loop();
    }

    void breakpoint_hit(u32 address) {
        this.was_breakpoint_hit = true;
    }

    void sigint() {
        interrupted = true;
    }

    void enter_gdb_run_loop() {
        interrupted            = false;
        was_breakpoint_hit     = false;
        needs_to_hang_at_start = false;

        while (true) {
            writef("\n > ");

            string command = readln[0 .. $ - 1];

            if (process_command(command)) {
                break;
            }
        }
    }

    bool process_command(string command) {
        foreach (i, cmd; commands) {
            if (command.startsWith(cmd.name) || command.startsWith(cmd.shortname)) {
                return cmd.handler(command);
            }
        }

        writef("  Unknown command: %s\n", command);
        return false;
    }

    bool show_help(string command) {
        writef("  Available commands:\n");
        foreach (cmd; commands) {
            writef("  %s (%s): %s\n", cmd.shortname, cmd.name, cmd.description);
        }
        return false;
    }

    bool continue_execution(string command) {
        cpu.exit_single_step_mode();
        return true;
    }

    bool create_breakpoint(string command) {
        auto parts = command.split(" ");
        if (parts.length < 2) {
            writef("  Usage: b <address>\n");
            return false;
        }

        try {
            auto address = parts[1].parse!u32(16);
            cpu.jit.add_breakpoint(address);
            writef("  Breakpoint set at %x\n", address);
        } catch (Exception e) {
            writef("  Invalid address: %s\n", e.msg);
        }
        return false;
    }

    bool show_gprs(string command) {
        writef("Registers:\n");
        for (int i = 0; i < 4; i++) {
            writef("  r%02d-%02d: %08x %08x %08x %08x %08x %08x %08x %08x\n", i * 8, i * 8 + 7,
                cpu.state.gprs[i * 8 + 0], cpu.state.gprs[i * 8 + 1], cpu.state.gprs[i * 8 + 2], cpu.state.gprs[i * 8 + 3],
                cpu.state.gprs[i * 8 + 4], cpu.state.gprs[i * 8 + 5], cpu.state.gprs[i * 8 + 6], cpu.state.gprs[i * 8 + 7]);
        }
        writef("  pc: %08x\n", cpu.state.pc);
        writef("  lr: %08x\n", cpu.state.lr);
        return false;
    }

    bool read_memory(string command) {
        auto parts = command.split(" ");
        if (parts.length < 3) {
            writef("  Usage: r <address> <size>\n");
            return false;
        }

        auto address = parts[1].parse!u32(16);
        auto size = parts[2].parse!u32(10);

        switch (size) {
            case 1: writef("  %02x\n", mem.cpu_read_u8(address)); break;
            case 2: writef("  %04x\n", mem.cpu_read_u16(address)); break;
            case 4: writef("  %08x\n", mem.cpu_read_u32(address)); break;
            default: writef("  Invalid size: %d\n", size); return false;
        }

        return false;
    }

    bool write_memory(string command) {
        auto parts = command.split(" ");
        if (parts.length < 4) {
            writef("  Usage: w <address> <size> <value>\n");
            return false;
        }

        auto address = parts[1].parse!u32(16);
        auto size = parts[2].parse!u32(10);
        auto value = parts[3].parse!u32(16);

        switch (size) {
            case 1: mem.cpu_write_u8(address, cast(u8)value); break;
            case 2: mem.cpu_write_u16(address, cast(u16)value); break;
            case 4: mem.cpu_write_u32(address, cast(u32)value); break;
            default: writef("  Invalid size: %d\n", size); return false;
        }

        return false;
    }

    bool log_memory_writes(string command) {
        auto parts = command.split(" ");
        if (parts.length < 2) {
            writef("  Usage: l <address>\n");
            return false;
        }

        auto address = parts[1].parse!u32(16);
        mem.log_memory_write(address);
        writef("  Logging memory writes at %x\n", address);
        return false;
    }

    bool step_instruction(string command) {
        cpu.enter_single_step_mode();
        return true;
    }

    bool show_stack(string command) {
        auto stack = cpu.state.gprs[1];
        writef("Stack:\n");
        for (int i = 0; i < 100; i++) {
            writef("  %08x: %08x\n", stack + i * 4, mem.cpu_read_u32(stack + i * 4));
        }
        return false;
    }

    bool quit_gdb(string command) {
        exit(0);
        return false;
    }

    void hang_at_start() {
        needs_to_hang_at_start = true;
    }
}