// im sorry to whoever is opening this file. everything is a mess of
// hardcoded values and a cacophony of shitty spaghetti code.
// i dont like emulating bluetooth, i dont like wiimotes, i just want
// to play my wii games in peace and continue emulating fun stuff
// like graphics and audio

module emu.hw.ipc.usb.bluetooth;

import emu.hw.ipc.ipc;
import emu.hw.ipc.usb.wiimote;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import std.container : DList;
import util.array;
import util.number;
import util.log;

struct HciEvt {
    u8 evt_code;
    u8 len;
}

enum Direction {
    HostToController = 0,
    ControllerToHost = 1,
}

final class Bluetooth {
    u32 hci_paddr = 0;
    u32 acl_paddr = 0;

    u8[3] call_of_duty;

    IPCResponseQueue ipc_response_queue;
    this(IPCResponseQueue response_queue) {
        this.ipc_response_queue = response_queue;
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    Scheduler scheduler;
    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_wiimote(Wiimote wiimote) {
        this.wiimote = wiimote;
    }

    DList!(u8[]) pending_hci;
    DList!(u8[]) pending_acl;

    Wiimote wiimote;
    bool scanning;

    u8[] hci_request(Direction direction, u32 paddr, u8[] data) {
        log_bluetooth("BT HCI request: %s", direction);

        if (direction == Direction.ControllerToHost) {
            hci_paddr = paddr;
        } 

        update();

        return [];
    }

    u8[] acl_request(Direction direction, u32 paddr, u8[] data) {
        log_bluetooth("BT ACL request: %s", direction);

        if (direction == Direction.ControllerToHost) {
            acl_paddr = paddr;
        } else {
            wiimote.handle_l2cap(data);
            send_hci_response([0x13, 0x15, 0x05, 0x00, 0x01, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x04, 0x01, 0x00, 0x00]);
            ipc_response_queue.push_later(paddr, 0, 10_000);
        }

        update();

        return [];
    }

    u8[] hci_control_request(u32 paddr, u8[] data) {
        log_bluetooth("HCI control request: %s", data.to_hex_string);

        if (data.length < 3) {
            return [];
        }

        auto ogf = data[1] >> 2;
        auto ocf = ((data[1] & 0x03) << 8) | data[0];
        log_bluetooth("HCI control request: ogf=%d ocf=%04x %x %x", ogf, ocf, data[0], data[1]);

        switch (ogf) {
            case 0x01: hci_control_request_link(ocf, data); break;
            case 0x02: hci_control_request_link_policy(ocf, data); break;
            case 0x03: hci_control_request_baseband(ocf, data); break;
            case 0x04: hci_control_request_informational(ocf, data[2..$]); break;
            case 0x3f: hci_control_request_vendor(ocf, data[2..$]); break;
            default: error_bluetooth("unimplemented HCI control request: ogf=%d ocf=%04x", ogf, ocf);
        }

        u32 ioctl_vector = mem.paddr_read_u32(paddr + 0x18);
        log_bluetooth("pushing to paddr: %x", ioctl_vector);
        ipc_response_queue.push_later(paddr, cast(int)  mem.paddr_read_u32(ioctl_vector + 52), 40_000);

        update();

        return [];
    }

    void hci_control_request_vendor(int ocf, u8[] data) {
        switch (ocf) {
            case 0x4c: return hci_control_request_vendor_who_knows(data);
            case 0x4f: return hci_control_request_vendor_who_cares(data);
            default: error_bluetooth("unimplemented HCI control vendor request: ocf=%04x", ocf);
        }
    }

    // 45 47 43 24 18 
    void hci_control_request_baseband(int ocf, u8[] data) {
        switch (ocf) {
            case 0x003: return hci_control_request_baseband_reset(data);
            case 0x00a: return hci_control_request_baseband_write_pin_type(data);
            case 0x00d: return hci_control_request_baseband_read_stored_link_keys(data);
            case 0x012: return hci_control_request_baseband_delete_stored_link_key(data);
            case 0x013: return hci_control_request_write_local_name(data);
            case 0x018: return hci_control_request_baseband_write_page_timeout(data);
            case 0x01a: return hci_control_request_baseband_write_scan_enable(data);
            case 0x024: return hci_control_request_baseband_write_call_of_duty(data);
            case 0x033: return hci_control_request_baseband_host_buffer_size(data);
            case 0x037: return hci_control_request_baseband_write_link_supervision_timeout(data);
            case 0x043: return hci_control_request_baseband_write_inquiry_scan_type(data);
            case 0x045: return hci_control_request_baseband_write_inquiry_mode(data);
            case 0x047: return hci_control_request_baseband_write_page_scan_type(data);
            default: error_bluetooth("unimplemented HCI control baseband request: ocf=%04x", ocf);
        }
    }

    void hci_control_request_informational(int ocf, u8[] data) {
        switch (ocf) {
            case 0x001: return hci_control_request_informational_read_local_version(data);
            case 0x003: return hci_control_request_informational_read_local_features(data);
            case 0x005: return hci_control_request_informational_read_buffer_size(data);
            case 0x009: return hci_control_request_informational_read_bd_addr(data);
            default: error_bluetooth("unimplemented HCI control informational request: ocf=%04x", ocf);
        }
    }

    void hci_control_request_link(int ocf, u8[] data) {
        switch (ocf) {
            case 0x009: return hci_control_request_link_accept_connection(data);
            case 0x00f: return hci_control_request_link_change_packet_type(data);
            case 0x011: return hci_control_request_link_auth_complete(data);
            case 0x019: return hci_control_request_link_get_name(data);
            case 0x01b: return hci_control_request_link_useless_bullshit(data);
            case 0x01d: return hci_control_request_link_get_lmp_subversion(data);
            case 0x01f: return hci_control_request_link_get_clock_offset(data);
            default: error_bluetooth("unimplemented HCI control link request: ocf=%04x", ocf);
        }
    }

    void hci_control_request_link_policy(int ocf, u8[] data) {
        switch (ocf) {
            case 0x003: return hci_control_request_link_policy_sniff_mode(data);
            case 0x00d: return hci_control_request_link_policy_write_settings(data);
            default: error_bluetooth("unimplemented HCI control link policy request: ocf=%04x", ocf);
        }
    }

    void hci_control_request_baseband_reset(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x03, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband reset");
    }

    void hci_control_request_baseband_write_call_of_duty(u8[] data) {
        call_of_duty = data[2..5];
        send_hci_response([0xe, 0x04, 0x01, 0x24, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband write call of duty");
    }

    void hci_control_request_write_local_name(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x13, 0x0c, 0x00]);
        log_bluetooth("HCI control request: write local name");
    }

    void hci_control_request_informational_read_buffer_size(u8[] data) {
        send_hci_response([0xe, 0x0b, 0x01, 0x05, 0x10, 0x00, 0x53, 0x01, 0x40, 0x0a, 0x00, 0x00, 0x00]);
        log_bluetooth("HCI control request: informational read buffer size");
    }

    void hci_control_request_baseband_write_pin_type(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x0a, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband write pin type");
    }

    void hci_control_request_baseband_host_buffer_size(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x33, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband host buffer size");
    }

    void hci_control_request_baseband_write_link_supervision_timeout(u8[] data) {
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x0d, 0x08]);
        log_bluetooth("HCI control request: baseband write link supervision timeout");
    }

    void hci_control_request_informational_read_local_version(u8[] data) {
        send_hci_response([0xe, 0x0c, 0x01, 0x01, 0x10, 0x00, 0x03, 0xa7, 0x40, 0x03, 0x0f, 0x00, 0x0e, 0x43]);
        log_bluetooth("HCI control request: informational read local version");
    }

    void hci_control_request_informational_read_local_features(u8[] data) {
        send_hci_response([0xe, 0x0c, 0x01, 0x03, 0x10, 0x00, 0xff, 0xff, 0x8d, 0xfe, 0x9b, 0xf9, 0x00, 0x80]);
        log_bluetooth("HCI control request: informational read local features");
    }

    void hci_control_request_informational_read_bd_addr(u8[] data) {
        send_hci_response([0xe, 0x0a, 0x01, 0x09, 0x10, 0x00, 0x11, 0x02, 0x19, 0x79, 0x00, 0xff]);
        log_bluetooth("HCI control request: informational read bd addr");
    }

    void hci_control_request_baseband_write_page_timeout(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x18, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband write page timeout");
    }

    void hci_control_request_baseband_write_inquiry_scan_type(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x43, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband write inquiry scan type");
    }

    void hci_control_request_baseband_write_inquiry_mode(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x45, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband write inquiry mode");
    }

    void hci_control_request_baseband_write_page_scan_type(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x47, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband write page scan type");
    }

    void hci_control_request_baseband_read_stored_link_keys(u8[] data) {
        send_hci_response([0x15, 0x6f, 0x05, 0x11, 0x02, 0x19, 0x79, 0x00, 0x00, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0x11, 0x02, 0x19, 0x79, 0x00, 0x01, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0x11, 0x02, 0x19, 0x79, 0x00, 0x02, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0x11, 0x02, 0x19, 0x79, 0x00, 0x03, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0x11, 0x02, 0x19, 0x79, 0x00, 0x04, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4]);
        send_hci_response([0xe, 0x08, 0x01, 0x0d, 0x0c, 0x00, 0xff, 0x00, 0x05, 0x00]);
        log_bluetooth("HCI control request: baseband read stored link keys");
    }

    void hci_control_request_baseband_delete_stored_link_key(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x12, 0x0c, 0x00]);
        log_bluetooth("HCI control request: baseband delete stored link key");
    }

    void hci_control_request_vendor_who_knows(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x4c, 0xfc, 0x00]);
        log_bluetooth("HCI control request: vendor who knows");
    }

    void hci_control_request_vendor_who_cares(u8[] data) {
        send_hci_response([0xe, 0x04, 0x01, 0x4f, 0xfc, 0x00]);
        log_bluetooth("HCI control request: vendor who cares");
    }

    void hci_control_request_baseband_write_scan_enable(u8[] data) {
        u8 scan_type = data[3];
        if (scan_type != 0 && scan_type != 2) {
            error_bluetooth("unimplemented HCI control request: write scan enable scan_type=%02x", scan_type);
        }

        scanning = scan_type == 2;

        trivial_success(data);
    }

    void hci_control_request_link_policy_sniff_mode(u8[] data) {
        // heres the status
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x03, 0x08]);
        send_hci_response([0x14, 0x06, 0x00, 0x00, 0x01, 0x02, 0x08, 0x00]);
    }

    void hci_control_request_link_accept_connection(u8[] data) {
        // the fuck?
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x09, 0x04]);

        // hi im a slave
        send_hci_response([0x12, 0x08, 0x00, 0x11, 0x02, 0x19, 0x79, 0x00, 0x00, 0x00]);

        // connection complete please suck my dick
        send_hci_response([0x03, 0x0b, 0x00, 0x00, 0x01, 0x11, 0x02, 0x19, 0x79, 0x00, 0x00, 0x01, 0x00]);
        
        wiimote.finish_connecting();
    }    
    
    void hci_control_request_link_get_name(u8[] data) {
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x19, 0x04]);
        
        char[] response = [0x07, 0xff, 0x00, 0x11, 0x02, 0x19, 0x79, 0x00, 0x00];
        foreach (char c; "Nintendo RVL-CNT-01") {
            response ~= cast(u8) c;
        }

        for (int i = cast(int) response.length; i <= 257; i++) {
            response ~= 0;
        }

        send_hci_response(cast(u8[]) response);
    }

    void hci_control_request_link_get_clock_offset(u8[] data) {
        // heres the status
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x1f, 0x04]);
    
        // here is the offset of my cock
        send_hci_response([0x1c, 0x05, 0x00, 0x00, 0x01, 0x18, 0x38]);
    }

    void hci_control_request_link_get_lmp_subversion(u8[] data) {
        // heres the status
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x1d, 0x04]);
        send_hci_response([0x0c, 0x08, 0x00, 0x00, 0x01, 0x02, 0x0f, 0x00, 0x29, 0x02]);
    }

    void hci_control_request_link_useless_bullshit(u8[] data) {
        // heres the status
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x1b, 0x04]);
        send_hci_response([0x0b, 0x0b, 0x00, 0x00, 0x01, 0xbc, 0x02, 0x04, 0x38, 0x08, 0x00, 0x00, 0x00]);
    }

    void hci_control_request_link_change_packet_type(u8[] data) {
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x0f, 0x04]);
        send_hci_response([0x1d, 0x05, 0x00, 0x00, 0x01, 0x18, 0xcc]);
    }

    void hci_control_request_link_auth_complete(u8[] data) {
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x11, 0x04]);
        send_hci_response([0x06, 0x03, 0x00, 0x00, 0x01]);
    }

    void hci_control_request_link_policy_write_settings(u8[] data) {
        send_hci_response([0x0f, 0x04, 0x00, 0x01, 0x0d, 0x08]);
    }

    void trivial_success(u8[] data) {
        send_hci_response(cast(u8[]) [0xe, data.length + 1, 0x01] ~ data);
    }

    void copy_to_user_buf(u32 user_buf_addr, u8[] data, size_t user_buf_len) {
        log_bluetooth("copy_to_user_buf: %x %s %x", user_buf_addr, data.to_hex_string, user_buf_len);
        if (data.length > user_buf_len) error_bluetooth("fuck");

        for (int i = 0; i < data.length; i++) {
            mem.paddr_write_u8(user_buf_addr + i, data[i]);
        }
    }

    void update() {
        if (wiimote.is_disconnected() && scanning) {
            send_wiimote_connection_request();
        }

        if (!pending_acl.empty && acl_paddr != 0) {
            auto reply = pending_acl.front;
            pending_acl.removeFront();

            u32 acl_ioctl_vector = mem.paddr_read_u32(acl_paddr + 0x18);
            log_bluetooth("pushing to acl paddr: %x", acl_ioctl_vector);
            log_bluetooth("queued acl response: %s", reply.to_hex_string);
            copy_to_user_buf(mem.paddr_read_u32(acl_ioctl_vector + 16), reply,
                mem.paddr_read_u32(acl_ioctl_vector + 20));
            ipc_response_queue.push_later(acl_paddr, cast(int) reply.length, 40_000);
            acl_paddr = 0;
        }

        if (!pending_hci.empty && hci_paddr != 0) {
            auto reply = pending_hci.front;
            pending_hci.removeFront();

            u32 hci_ioctl_vector = mem.paddr_read_u32(hci_paddr + 0x18);
            log_bluetooth("pushing to hci paddr: %x", hci_ioctl_vector);
            log_bluetooth("queued hci response: %s", reply.to_hex_string);
            copy_to_user_buf(mem.paddr_read_u32(hci_ioctl_vector + 16), reply,
                mem.paddr_read_u32(hci_ioctl_vector + 20));
            ipc_response_queue.push_later(hci_paddr, cast(int) reply.length, 40_000);
            hci_paddr = 0;
        }
    }

    void send_wiimote_connection_request() {
        send_hci_response([0x04, 0x0a, 0x11, 0x02, 0x19, 0x79, 0x00, 0x00, 0x00, 0x04, 0x48, 0x01]);
        wiimote.start_connecting();
    }

    void send_hci_response(u8[] data) {
        log_bluetooth("send_hci_response(%s)", data.to_hex_string);
        pending_hci ~= data;
    }

    void send_acl_response(u8[] data) {
        log_bluetooth("send_acl_response(%s)", data.to_hex_string);
        pending_acl ~= data;
        update();
    }
}