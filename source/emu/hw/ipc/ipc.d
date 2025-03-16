module emu.hw.ipc.ipc;

import emu.hw.broadway.interrupt;
import emu.hw.disk.readers.filereader;
import emu.hw.ipc.filemanager;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.log;
import util.number;
import std.container : DList;
import std.stdio;

alias IPCResponseQueue = IPC.IPCResponseQueue;
final class IPC {
    struct IPCResponse {
        u32 paddr;
        int return_value;
    }

    final class IPCResponseQueue {
        IPC ipc;

        this(IPC ipc) {
            this.ipc = ipc;
        }

        DList!IPCResponse responses;
        int num_outstanding_responses = 0;

        void push_later(u32 paddr, int return_value, int cycles) {
            num_outstanding_responses++;
            log_ipc("FUCK MY ASS!\n");
            ipc.scheduler.add_event_relative_to_clock(() => push(paddr, return_value), cycles);
        }

        void push(u32 paddr, int return_value) {
            log_ipc("OUTSTANDING: %x", num_outstanding_responses);

            if (ipc.waiting_for_cpu_to_get_response) {
                IPCResponse response;
                response.paddr = paddr;
                response.return_value = return_value;
                responses.insertBack(response);
                log_ipc("IPC: Waiting for CPU to get response");
            } else {
                ipc.finalize_command(paddr, return_value);
                log_ipc("IPC: Waiting for CPU to get response");
                num_outstanding_responses--;
            }
        }

        void maybe_finalize_new_response() {
            log_ipc("OUTSTANDING: %x", num_outstanding_responses);
            
            if (!ipc.waiting_for_cpu_to_get_response && !responses.empty) {
                log_ipc("IPC: Finalizing new response");
                IPCResponse response = responses.front;
                responses.removeFront();
                ipc.scheduler.add_event_relative_to_clock(() => finalize_command(response.paddr, response.return_value), 10000);
                num_outstanding_responses--;
            }
        }

        bool empty() {
            return responses.empty;
        }
    }

    IPCResponseQueue response_queue;
    bool waiting_for_cpu_to_get_response = false;

    Mem mem;
    InterruptController interrupt_controller;

    Scheduler scheduler;
    ulong process_command_event_id;
    ulong finalize_command_event_id;

    FileManager file_manager;

    this() {
        response_queue = new IPCResponseQueue(this);
        file_manager = new FileManager(response_queue);

        hw_ipc_ppcmsg = 0;
        hw_ipc_ppcctrl = 0;
        hw_ipc_armmsg = 0;
    }

    void connect_mem(Mem mem) {
        this.mem = mem;
        this.file_manager.connect_mem(mem);
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

        log_ipc("IPC: Writing to HW_IPC_PPCCTRL = %x %x", hw_ipc_ppcctrl , value);
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
if (scheduler.current_timestamp == 0x0000000001c87894) mem.cpu.dump_stack();
        if (x1) {
            log_ipc("Sending command");

            auto paddr = hw_ipc_ppcmsg;
            u32 command = mem.paddr_read_u32(paddr + 0);

            process_command_event_id = scheduler.add_event_relative_to_clock(() => process_command(command, paddr), 10000);
        }

        if (!hw_ipc_ppcctrl.bit(2) && !hw_ipc_ppcctrl.bit(1) && !interrupt_controller.ipc_interrupt_pending()) {
            log_ipc("IPC: Interrupt acknowledged");
            
            waiting_for_cpu_to_get_response = false;
            response_queue.maybe_finalize_new_response();
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
        log_ipc("IPC: Reading from hw_ipc_armmsg[%d] = %x", target_byte, hw_ipc_armmsg.get_byte(target_byte));
        return hw_ipc_armmsg.get_byte(target_byte);
    }

    void process_command(u32 command, u32 paddr) {
        hw_ipc_ppcctrl |= 1 << 1;

        if (hw_ipc_ppcctrl.bit(5)) {
            log_ipc("Raising Interrupt1...");
            interrupt_controller.raise_hollywood_interrupt(HollywoodInterruptCause.IPC);
        }

        log_ipc("IPC::ProcessCommand: %x\n", command);

        switch (command) {
            case 1: ios_open(paddr);   return;
            case 2: ios_close(paddr);  return;
            case 3: ios_read(paddr);   return;
            case 4: ios_write(paddr);  return;
            case 5: ios_seek(paddr);   return;
            case 6: ios_ioctl(paddr);  return;
            case 7: ios_ioctlv(paddr); return;

            default: error_ipc("unimplemented command %x for fd %x", command, mem.paddr_read_u32(paddr + 8));
        }
    }

    void ios_seek(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        u32 where = mem.paddr_read_u32(paddr + 0xC);
        u32 whence = mem.paddr_read_u32(paddr + 0x10);
        log_ipc("IOS::Seek paddr: %x, fd: %d, where: %d, whence: %d", paddr, fd, where, whence);

        file_manager.seek(paddr, fd, where, whence);
    }

    void ios_open(u32 paddr) {
        u32 path_paddr = mem.paddr_read_u32(paddr + 0xC);
        u32 mode = mem.paddr_read_u32(paddr + 0x10);
        u32 uid = mem.paddr_read_u32(paddr + 0x14);
        u32 gid = mem.paddr_read_u32(paddr + 0x18);

        string path;
        log_ipc("Reading path from %x", path_paddr);
        for (int i = 0; i < 0x100; i++) {
            u8 c = mem.paddr_read_u8(path_paddr + i);
            if (c == 0) break;
            path ~= cast(char) c;
        }
        writefln("IOS::Open paddr: %x, path: %s, mode: %d, uid: %d, gid: %d\n", paddr, path, mode, uid, gid);
        file_manager.open(paddr, path, cast(OpenMode) mode, uid, gid);
    }

    void ios_close(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        file_manager.close(paddr, fd);

        log_ipc("IOS::Close paddr: %x, fd: %d", paddr, fd);
    }

    void ios_ioctl(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        u32 ioctl = mem.paddr_read_u32(paddr + 0xC);
        u32 input_buffer = mem.paddr_read_u32(paddr + 0x10);
        u32 input_buffer_length = mem.paddr_read_u32(paddr + 0x14);
        u32 output_buffer = mem.paddr_read_u32(paddr + 0x18);
        u32 output_buffer_length = mem.paddr_read_u32(paddr + 0x1C);
        log_ipc("IOS::Ioctl paddr: %x, fd: %d, ioctl: %d, input_buffer: %x, input_buffer_length: %d, output_buffer: %x, output_buffer_length: %d", paddr, fd, ioctl, input_buffer, input_buffer_length, output_buffer, output_buffer_length);

        // wtf?

        file_manager.ioctl(paddr, fd, ioctl, input_buffer, input_buffer_length, output_buffer, output_buffer_length);
    }

    void ios_read(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        u32 buffer_paddr = mem.paddr_read_u32(paddr + 0xC);
        u32 size = mem.paddr_read_u32(paddr + 0x10);
        log_ipc("IOS::Read paddr: %x, fd: %d, buffer_paddr: %x, size: %d", paddr, fd, buffer_paddr, size);

        u8[] buffer = new u8[size];
        file_manager.read(paddr, fd, size, buffer);
    }

    void ios_write(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        u32 buffer_paddr = mem.paddr_read_u32(paddr + 0xC);
        u32 size = mem.paddr_read_u32(paddr + 0x10);
        log_ipc("IOS::Write paddr: %x, fd: %d, buffer_paddr: %x, size: %d", paddr, fd, buffer_paddr, size);

        u8[] buffer = new u8[size];
        for (int i = 0; i < size; i++) {
            buffer[i] = mem.paddr_read_u8(buffer_paddr + i);
            if (fd == 4) {
                log_ipc("    IOS::Write[%d]: %x", i, buffer[i]);
            }
        }

        file_manager.write(paddr, fd, size, buffer.ptr);
    }

    void ios_ioctlv(u32 paddr) {
        u32 fd = mem.paddr_read_u32(paddr + 8);
        u32 ioctl = mem.paddr_read_u32(paddr + 0xC);
        u32 argcin = mem.paddr_read_u32(paddr + 0x10);
        u32 argcio = mem.paddr_read_u32(paddr + 0x14);
        u32 ioctlv_struct = mem.paddr_read_u32(paddr + 0x18);
        log_ipc("IOS::Ioctlv paddr: %x, fd: %d, ioctl: %d, argcin: %d, argcio: %d, ioctlv_struct: %x", paddr, fd, ioctl, argcin, argcio, ioctlv_struct);
        file_manager.ioctlv(paddr, fd, ioctl, argcin, argcio, ioctlv_struct);
    }

    // void ios_return(u32 paddr, int return_value) {
        // state = State.WaitingForCommand;

        // finalize_command_event_id = scheduler.add_event_relative_to_self(() => finalize_command(paddr, return_value), 40000);
    // }

    void finalize_command(u32 paddr, int return_value) {
        waiting_for_cpu_to_get_response = true;
        mem.paddr_write_u32(paddr + 4, *(cast(u32*) &return_value));
        for (int i = 0; i < 0x1c; i += 4) {
            log_ipc("COMMAND[%d]: %08x", i, mem.paddr_read_u32(paddr + i));
        }

        log_ipc("Finalizing command %x with return value %x", paddr, return_value);
        hw_ipc_ppcctrl |= 1 << 2;

        log_ipc("Set hw_ipc_armmsg to %x", paddr);
        hw_ipc_armmsg = paddr;

        if (hw_ipc_ppcctrl.bit(4)) {
            log_ipc("Raising IPCIRQ: %x", interrupt_controller.ipc_interrupt_pending());
            interrupt_controller.raise_hollywood_interrupt(HollywoodInterruptCause.IPC);
        }
    }

    void load_sysconf(ubyte[] sysconf) {
        file_manager.load_sysconf(sysconf);
    }

    void load_file_reader(FileReader reader) {
        file_manager.load_file_reader(reader);
    }

    void set_title_id(u64 title_id) {
        file_manager.set_title_id(title_id);
    }

    void interrupt_acknowledged() {
        log_hollywood("ipc: %x ", hw_ipc_ppcctrl);
        if (!hw_ipc_ppcctrl.bit(2) && !hw_ipc_ppcctrl.bit(1)) {
            waiting_for_cpu_to_get_response = false;
            response_queue.maybe_finalize_new_response();
        }
    }
}