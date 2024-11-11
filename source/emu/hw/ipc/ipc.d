module emu.hw.ipc.ipc;

import emu.hw.broadway.interrupt;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.log;
import util.number;

final class IPC {
    enum State {
        WaitingForCommand,
        ProcessingCommand
    }

    State state = State.WaitingForCommand;

    Mem mem;
    InterruptController interrupt_controller;

    Scheduler scheduler;
    ulong process_command_event_id;
    ulong finalize_command_event_id;

    this() {

    }

    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_interrupt_controller(InterruptController ic) {
        this.interrupt_controller = ic;
    }

    u32 hw_ipc_ppcmsg;
    void write_HW_IPC_PPCMSG(int target_byte, u8 value) {
        log_ipc("IPC: Writing to HW_IPC_PPCMSG[%d] = %x", target_byte, value);
        hw_ipc_ppcmsg = hw_ipc_ppcmsg.set_byte(target_byte, value);
    }

    u8 read_HW_IPC_PPCMSG(int target_byte) {
        log_ipc("IPC: Reading from HW_IPC_PPCMSG[%d] = %x", target_byte, hw_ipc_ppcmsg.get_byte(target_byte));
        return hw_ipc_ppcmsg.get_byte(target_byte);
    }

    u32 hw_ipc_ppcctrl;

    void write_HW_IPC_PPCCTRL(T)(T value, int offset) {
        assert(offset == 0, "IPC: PPCCTRL offset is not 0");
        assert(T.sizeof == 4, "IPC: PPCCTRL write size is not 4");

        log_ipc("IPC: Writing to HW_IPC_PPCCTRL = %x", value);
        if (value.bit(1)) hw_ipc_ppcctrl &= ~(1 << 1);
        if (value.bit(2)) hw_ipc_ppcctrl &= ~(1 << 2);
        
        hw_ipc_ppcctrl &= 6;
        hw_ipc_ppcctrl |= cast(u32) value & ~6;

        log_ipc("IPC: HW_IPC_PPCCTRL = %x (cpu pc: %x)", hw_ipc_ppcctrl, interrupt_controller.broadway.state.pc);

        bool x1  = hw_ipc_ppcctrl.bit(0);
        bool y2  = hw_ipc_ppcctrl.bit(1);
        bool y1  = hw_ipc_ppcctrl.bit(2);
        bool x2  = hw_ipc_ppcctrl.bit(3);
        bool iy1 = hw_ipc_ppcctrl.bit(4);
        bool iy2 = hw_ipc_ppcctrl.bit(5);

        if (x2) {
            // hw_ipc_ppcctrl &= ~0xF;
            // scheduler.remove_event(process_command_event_id);
            // scheduler.remove_event(finalize_command_event_id);

            // log_ipc("Relaunching IOS");
            return;
        } 

        if (x1) {
            if (state != State.WaitingForCommand) {
                error_ipc("Received two commands at once");
            }

            state = State.ProcessingCommand;

            auto paddr = hw_ipc_ppcmsg;
            u32 command = mem.paddr_read_u32(paddr + 0);

            process_command_event_id = scheduler.add_event_relative_to_clock(() => process_command(command, paddr), 10000);
        }
    }

    T read_HW_IPC_PPCCTRL(T)(int offset) {
        assert(offset == 0, "IPC: PPCCTRL offset is not 0");
        assert(T.sizeof == 4, "IPC: PPCCTRL write size is not 4");

        log_ipc("Reading %x hw_ipc_ppcctrl from %x", cast(T) hw_ipc_ppcctrl, interrupt_controller.broadway.state.pc);
        return cast(T) hw_ipc_ppcctrl;
    }

    u32 hw_ipc_armmsg;

    u8 read_HW_IPC_ARMMSG(int target_byte) {
        interrupt_controller.broadway.biglog = true;
        return hw_ipc_armmsg.get_byte(target_byte);
    }

    void process_command(u32 command, u32 paddr) {
        hw_ipc_ppcctrl |= 1 << 1;

        if (hw_ipc_ppcctrl.bit(5)) {
            log_ipc("Raising Interrupt1...");
            interrupt_controller.raise_hollywood_interrupt(HollywoodInterruptCause.IPC);
        }

        switch (command) {
            case 2: ios_close(paddr); return;

            default: error_ipc("unimplemented command %x", command);
        }
    }

    void ios_close(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        log_ipc("IOS::close(%x)", fd);
        ios_return(paddr, 0);
    }

    void ios_return(u32 paddr, u32 return_value) {
        state = State.WaitingForCommand;

        finalize_command_event_id = scheduler.add_event_relative_to_self(() => finalize_command(paddr, return_value), 40000);
    }

    void finalize_command(u32 paddr, u32 return_value) {
        for (int i = 0; i < 0x40; i += 4) {
            log_ipc("COMMAND[%d]: %08x", i, mem.paddr_read_u32(paddr + i));
        }
        mem.paddr_write_u32(paddr + 4, return_value);
        mem.paddr_write_u32(paddr + 8, mem.paddr_read_u32(paddr + 0));

        hw_ipc_ppcctrl |= 1 << 2;
        hw_ipc_armmsg = paddr;

        state = State.WaitingForCommand;

        if (hw_ipc_ppcctrl.bit(4)) {
            log_ipc("Raising Interrupt2...");
            interrupt_controller.raise_hollywood_interrupt(HollywoodInterruptCause.IPC);
        }
    }
}