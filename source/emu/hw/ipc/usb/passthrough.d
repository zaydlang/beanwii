module emu.hw.ipc.usb.passthrough;

import emu.hw.ipc.ipc;
import emu.hw.memory.strategy.memstrategy;
import util.number;
import util.log;

extern(C) {
	int hci_get_route(char[] buf);
	int hci_open_dev(int dev_id);
	int hci_send_cmd(int dd, int ogf, int ocf, int plen, void *param);
}

enum Direction {
    HostToController = 0,
    ControllerToHost = 1,
}

final class BluetoothPassthrough {
    u8[] hci_buffer;

    u32 hci_paddr = 0;
    u32 acl_paddr = 0;

    int dev_id;
    int dd;

    IPCResponseQueue ipc_response_queue;
    this(IPCResponseQueue response_queue) {
        this.ipc_response_queue = response_queue;
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    void connect() {
        this.dev_id = hci_get_route(null);
        if (this.dev_id < 0) {
            error_bluetooth("No Bluetooth device found");
            return;
        }

        this.dd = hci_open_dev(this.dev_id);
        if (this.dd < 0) {
            error_bluetooth("Failed to open Bluetooth device");
            return;
        }        
    }

    u8[] hci_request(Direction direction, u32 paddr, u8[] data) {
        if (direction == Direction.ControllerToHost) {
            hci_paddr = paddr;
        } 

        log_bluetooth("HCI request: %x", data.length);
        return [];
    }

    u8[] acl_request(u32 paddr, u8[] data) {
        acl_paddr = paddr;
        log_bluetooth("ACL request: %x", data.length);

        return [];
    }

    u8[] hci_control_request(u32 paddr, u8[] data) {
        log_bluetooth("HCI control request: %s", data);

        if (data.length < 3) {
            return [];
        }

        auto ogf = data[1] >> 2;
        auto ocf = ((data[1] & 0x03) << 8) | data[0];

        log_bluetooth("hci_send_cmd(%x, %x, %x, %x, %s)", this.dd, ogf, ocf, cast(int) data.length - 3, data[3..$]);
        auto result = hci_send_cmd(this.dd, ogf, ocf, cast(int) data.length - 3, data[3..$].ptr);
        log_bluetooth("hci_send_cmd result: %d %s", result, data);
        trivial_success(data);

        // is this correct? legitimately what the fuck is going on anymore
        if (hci_paddr != 0) {
            u32 hci_ioctl_vector = mem.physical_read_u32(hci_paddr + 0x18);
            copy_to_user_buf(mem.physical_read_u32(hci_ioctl_vector + 16), hci_buffer,
                mem.physical_read_u32(hci_ioctl_vector + 20));
            ipc_response_queue.push_later(hci_paddr, cast(int) hci_buffer.length, 40_000);
            hci_buffer = [];
        }

        u32 ioctl_vector = mem.physical_read_u32(paddr + 0x18);
        ipc_response_queue.push_later(paddr, cast(int)  mem.physical_read_u32(ioctl_vector + 52), 40_000);

        return [];
    }

    void copy_to_user_buf(u32 user_buf_addr, u8[] data, size_t user_buf_len) {
        if (data.length > user_buf_len) error_bluetooth("fuck");

        for (int i = 0; i < data.length; i++) {
            mem.physical_write_u8(user_buf_addr + i, data[i]);
        }
    }

    u8[] trivial_success(u8[] data) {
        u8[] response = cast(u8[]) [0xe, data.length + 1, 0x01] ~ data;
        hci_buffer ~= response;

        return response;
    }
}
