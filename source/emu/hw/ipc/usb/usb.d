module emu.hw.ipc.usb.usb;

import emu.hw.ipc.ipc;
import emu.hw.ipc.usb.passthrough;
import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.number;
import util.log;

final class USBManager {
    BluetoothPassthrough bluetooth;

    IPCResponseQueue ipc_response_queue;    
    this(IPCResponseQueue response_queue) {
        this.ipc_response_queue = response_queue;
        bluetooth = new BluetoothPassthrough(response_queue);
        bluetooth.connect();
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
        bluetooth.connect_mem(mem);
    }

    u8[] interrupt_request(u32 paddr, u8 endpoint, u8[] data) {
        log_usb("USBManager: interrupt: endpoint=%02x %x", endpoint, data.length);

        int endpoint_number = endpoint.bits(0, 3);
        int direction = endpoint.bit(7);

        if (direction == 1) {
            if (endpoint_number == 1) {
                return bluetooth.hci_request(cast(Direction) direction, paddr, data);
            } else {
                log_usb("USBManager: interrupt: unknown endpoint");
            }
        } else {
            log_usb("USBManager: interrupt: unknown direction");
        }

        return [];
    }

    u8[] bulk_request(u32 paddr, u8 endpoint, u8[] data) {
        log_usb("USBManager: bulk: endpoint=%02x %x", endpoint, data.length);
        log_usb("USBManager: bulk: data=%s", data);
        int endpoint_number = endpoint.bits(0, 3);
        int direction = endpoint.bit(7);

        if (direction == 1) {
            if (endpoint_number == 2) {
                return bluetooth.acl_request(paddr, data);
            } else {
                log_usb("USBManager: bulk: unknown endpoint");
            }
        } else {
            log_usb("USBManager: bulk: unknown direction");
        }

        return [];
    }
    
    u8[] control_request(u32 paddr, u8 bm_request_type, u8 b_request, u16 w_value, u16 w_index, u16 w_length, u8[] data) {
        log_usb("USBManager: request: bm_request_type=%02x, b_request=%02x, w_value=%04x, w_index=%04x, w_length=%04x", bm_request_type, b_request, w_value, w_index, w_length);
        log_usb("USBManager: request: data=%s", data);

        return bluetooth.hci_control_request(paddr, data);
    }
}