// im sorry to whoever is opening this file. everything is a mess of
// hardcoded values and a cacophony of shitty spaghetti code.
// i dont like emulating bluetooth, i dont like wiimotes, i just want
// to play my wii games in peace and continue emulating fun stuff
// like graphics and audio

module emu.hw.ipc.usb.bluetooth;

import emu.hw.ipc.ipc;
import emu.hw.ipc.usb.wiimote;
import emu.hw.ipc.usb.bluetooth_types;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import std.container : DList;
import std.algorithm : min;
import std.traits : hasMember;
import util.array;
import util.bitop;
import util.endian;
import util.log;
import util.number;

u8[] struct_to_bytes(T)(ref T s) {
    return (cast(u8*)&s)[0..T.sizeof].dup;
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

    void connect_wiimotes(Wiimote[2] wiimotes) {
        this.wiimotes = wiimotes;

        this.wiimotes[0].bd_addr = [0x11, 0x02, 0x19, 0x79, 0x00, 0x00];
        this.wiimotes[0].connection_handle = 0x0100;
        this.wiimotes[1].bd_addr = [0x11, 0x02, 0x19, 0x79, 0x00, 0x01];
        this.wiimotes[1].connection_handle = 0x0101;
    }

    DList!(u8[]) pending_hci;
    DList!(u8[]) pending_acl;

    Wiimote[2] wiimotes;
    int wiimotes_to_connect = 1;
    bool scanning;

    Wiimote get_wiimote_by_bdaddr(u8[6] bd_addr) {
        foreach (wm; wiimotes) {
            if (wm.bd_addr == bd_addr) {
                return wm;
            }
        }

        error_bluetooth("no wiimote with bdaddr %s", bd_addr.to_hex_string);
        return null;
    }

    Wiimote get_wiimote_by_connection_handle(u16 connection_handle) {
        foreach (wm; wiimotes) {
            if (wm.connection_handle == connection_handle) {
                return wm;
            }
        }

        error_bluetooth("no wiimote with connection handle %x", connection_handle);
        return null;
    }

    Wiimote first_disconnected_wiimote() {
        foreach (i, wm; wiimotes) {
            if (!wiimote_connection_allowed(i)) {
                continue;
            }

            if (wm.state == WiimoteState.Disconnected) {
                return wm;
            }
        }

        error_bluetooth("no disconnected wiimote available");
        return null;
    }

    bool no_wiimotes_currently_connecting() {
        foreach (wm; wiimotes) {
            if (wm.state == WiimoteState.Connecting) {
                return false;
            }
        }

        return true;
    }
    bool exists_disconnected_wiimote() {
        foreach (i, wm; wiimotes) {
            if (!wiimote_connection_allowed(i)) {
                continue;
            }

            if (wm.state == WiimoteState.Disconnected) {
                return true;
            }
        }

        return false;
    }

    bool wiimote_connection_allowed(size_t index) {
        return index < wiimotes_to_connect;
    }

    void increment_wiimotes_to_connect() {
        wiimotes_to_connect = min(wiimotes_to_connect + 1, cast(int) wiimotes.length);
    }

    u8[] hci_request(Direction direction, u32 paddr, u8[] data) {
        log_bluetooth("BT HCI request: %s", direction);

        if (direction == Direction.ControllerToHost) {
            hci_paddr = paddr;
        } 

        update();

        return [];
    }

    u8[] acl_request(Direction direction, u32 paddr, u8[] data) {
        if (direction == Direction.ControllerToHost) {
            acl_paddr = paddr;
        } else {
            import std.stdio;
            writefln("Remote -> Device: %s", data.to_hex_string);
            HciAclHeader* acl_header = cast(HciAclHeader*) data.ptr;
            u16 requested_connection_handle = acl_header.handle_and_flags.bits(0, 11);

            Wiimote wiimote = get_wiimote_by_connection_handle(requested_connection_handle);
            wiimote.handle_l2cap(data[HciAclHeader.sizeof .. $]);

            HciAclPacketCountResponse response = {
                event_code: HciEventCode.NumberOfCompletedPackets,
                parameter_length: 21,
                num_handles: 5,
                handle_data: []
            };

            for (int i = 0; i < 5; i++) {
                HciAclPacketCountResponse.HandleData handle_data = {
                    connection_handle: 0,
                    num_acl_packets: 0
                };

                response.handle_data[i] = handle_data;
            }

            for (int i = 0; i < 2; i++) {
                HciAclPacketCountResponse.HandleData handle_data = {
                    connection_handle: wiimotes[i].connection_handle,
                    num_acl_packets: cast(u16) wiimotes[i].num_acl_packets_processed
                };

                wiimotes[i].num_acl_packets_processed = 0;                
                response.handle_data[i] = handle_data;
            }

            send_hci_response(struct_to_bytes(response));
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

        u32 ioctl_vector = mem.physical_read_u32(paddr + 0x18);
        log_bluetooth("pushing to paddr: %x", ioctl_vector);
        ipc_response_queue.push_later(paddr, cast(int)  mem.physical_read_u32(ioctl_vector + 52), 40_000);

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
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.Reset),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband reset");
    }

    void hci_control_request_baseband_write_call_of_duty(u8[] data) {
        call_of_duty = data[2..5];
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WriteClassOfDevice),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write call of duty");
    }

    void hci_control_request_write_local_name(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WriteLocalName),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: write local name");
    }

    void hci_control_request_informational_read_buffer_size(u8[] data) {
        HciReadBufferSizeResponse response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 11,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.ReadBufferSize),
            status: 0x00,
            hc_acl_data_packet_length: u16_le(0x0153),
            hc_synchronous_data_packet_length: 0x40,
            hc_total_num_acl_data_packets: u16_le(0x000A),
            hc_total_num_synchronous_data_packets: u16_le(0x0000)
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: informational read buffer size");
    }

    void hci_control_request_baseband_write_pin_type(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WritePinType),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write pin type");
    }

    void hci_control_request_baseband_host_buffer_size(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.HostBufferSize),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband host buffer size");
    }

    void hci_control_request_baseband_write_link_supervision_timeout(u8[] data) {
        HciCommandStatusEvent response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WriteLinkSupervisionTimeout)
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write link supervision timeout");
    }

    void hci_control_request_informational_read_local_version(u8[] data) {
        HciReadLocalVersionResponse response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 12,
            num_hci_command_packets: 1,
            command_opcode: HciCommandOpcode.ReadLocalVersionInformation,
            status: 0x00,
            hci_version: 0x03,
            hci_revision: 0x40A7,
            lmp_pal_version: 0x03,
            manufacturer_name: 0x000F,
            lmp_pal_subversion: 0x430E
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: informational read local version");
    }

    void hci_control_request_informational_read_local_features(u8[] data) {
        HciReadLocalFeaturesResponse response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 12,
            num_hci_command_packets: 1,
            command_opcode: HciCommandOpcode.ReadLocalSupportedFeatures,
            status: 0x00,
            lmp_features: [0xff, 0xff, 0x8d, 0xfe, 0x9b, 0xf9, 0x00, 0x80]
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: informational read local features");
    }

    void hci_control_request_informational_read_bd_addr(u8[] data) {
        HciReadBdAddrResponse response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 10,
            num_hci_command_packets: 1,
            command_opcode: HciCommandOpcode.ReadBdAddr,
            status: 0x00,
            bd_addr: [0x11, 0x02, 0x19, 0x79, 0x00, 0xff]
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: informational read bd addr");
    }

    void hci_control_request_baseband_write_page_timeout(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WritePageTimeout),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write page timeout");
    }

    void hci_control_request_baseband_write_inquiry_scan_type(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WriteInquiryScanType),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write inquiry scan type");
    }

    void hci_control_request_baseband_write_inquiry_mode(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WriteInquiryMode),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write inquiry mode");
    }

    void hci_control_request_baseband_write_page_scan_type(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.WritePageScanType),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband write page scan type");
    }

    void hci_control_request_baseband_read_stored_link_keys(u8[] data) {
        HciReadStoredLinkKeysResponse link_key_response = {
            event_code: HciEventCode.ReadStoredLinkKeyComplete,
            parameter_length: 111,
            num_keys: 5,
            link_keys: [
                {bd_addr: [0x11, 0x02, 0x19, 0x79, 0x00, 0x00], link_key: [0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0, 0xa0]},
                {bd_addr: [0x11, 0x02, 0x19, 0x79, 0x00, 0x01], link_key: [0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1, 0xa1]},
                {bd_addr: [0x11, 0x02, 0x19, 0x79, 0x00, 0x02], link_key: [0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2, 0xa2]},
                {bd_addr: [0x11, 0x02, 0x19, 0x79, 0x00, 0x03], link_key: [0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3, 0xa3]},
                {bd_addr: [0x11, 0x02, 0x19, 0x79, 0x00, 0x04], link_key: [0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4, 0xa4]}
            ]
        };
        send_hci_response(struct_to_bytes(link_key_response));
        ReadStoredLinkKeyCommandCompleteResponse complete_response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 8,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.ReadStoredLinkKey),
            status: 0x00,
            max_num_keys: u16_le(0x00FF),
            num_keys_read: u16_le(0x0005)
        };
        send_hci_response(struct_to_bytes(complete_response));
        log_bluetooth("HCI control request: baseband read stored link keys");
    }

    void hci_control_request_baseband_delete_stored_link_key(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.DeleteStoredLinkKey),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: baseband delete stored link key");
    }

    void hci_control_request_vendor_who_knows(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.VendorSpecific4C),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
        log_bluetooth("HCI control request: vendor who knows");
    }

    void hci_control_request_vendor_who_cares(u8[] data) {
        HciCommandCompleteEvent response = {
            event_code: HciEventCode.CommandComplete,
            parameter_length: 4,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.VendorSpecific4F),
            status: 0x00
        };
        send_hci_response(struct_to_bytes(response));
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
        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.SniffMode)
        };
        send_hci_response(struct_to_bytes(status_response));
        
        u16 requested_connection_handle = data.read_le!u16(3);

        HciModeChangeEvent mode_response = {
            event_code: HciEventCode.ModeChange,
            parameter_length: 6,
            status: 0x00,
            connection_handle: requested_connection_handle,
            current_mode: 0x02,
            interval: u16_be(0x0800)
        };
        send_hci_response(struct_to_bytes(mode_response));
    }

    void hci_control_request_link_accept_connection(u8[] data) {
        u8[6] connected_bdaddr = data[3..9];
        u16 connection_handle = connected_bdaddr[5] + 0x100;

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16) HciCommandOpcode.AcceptConnectionRequest)
        };
        send_hci_response(struct_to_bytes(status_response));

        HciRoleChangeEvent role_response = {
            event_code: HciEventCode.RoleChange,
            parameter_length: 8,
            status: 0x00,
            bd_addr: connected_bdaddr,
            new_role: 0x00
        };
        send_hci_response(struct_to_bytes(role_response));

        HciConnectionCompleteEvent connection_response = {
            event_code: HciEventCode.ConnectionComplete,
            parameter_length: 11,
            status: 0x00,
            connection_handle: connection_handle,
            bd_addr: connected_bdaddr,
            link_type: 0x01,
            encryption_enabled: 0x00
        };
        send_hci_response(struct_to_bytes(connection_response));
        
        auto wiimote = get_wiimote_by_bdaddr(connected_bdaddr);
        wiimote.finish_connecting();
    }    
    
    void hci_control_request_link_get_name(u8[] data) {
        u8[6] connected_bdaddr = data[3..9];

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.RemoteNameRequest)
        };
        send_hci_response(struct_to_bytes(status_response));
        
        ubyte[] response;
        response ~= [0x07, 0xff, 0x00];
        response ~= connected_bdaddr[];
        foreach (char c; "Nintendo RVL-CNT-01") {
            response ~= cast(u8) c;
        }

        for (int i = cast(int) response.length; i <= 257; i++) {
            response ~= 0;
        }

        send_hci_response(response);
    }

    void hci_control_request_link_get_clock_offset(u8[] data) {
        u16 requested_connection_handle = data.read_le!u16(3);

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.ReadClockOffset)
        };
        send_hci_response(struct_to_bytes(status_response));
    
        HciReadClockOffsetCompleteEvent offset_response = {
            event_code: HciEventCode.ReadClockOffsetComplete,
            parameter_length: 5,
            status: 0x00,
            connection_handle: requested_connection_handle,
            clock_offset: u16_le(0x3818)
        };
        send_hci_response(struct_to_bytes(offset_response));
    }

    void hci_control_request_link_get_lmp_subversion(u8[] data) {
        u16 requested_connection_handle = data.read_le!u16(3);

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: cast(u16) HciCommandOpcode.ReadRemoteVersionInformation
        };
        send_hci_response(struct_to_bytes(status_response));
        
        HciReadRemoteVersionCompleteEvent version_response = {
            event_code: HciEventCode.ReadRemoteVersionInformationComplete,
            parameter_length: 8,
            status: 0x00,
            connection_handle: requested_connection_handle,
            lmp_pal_version: 0x02,
            manufacturer_name: 0x000F,
            lmp_pal_subversion: 0x0229
        };
        send_hci_response(struct_to_bytes(version_response));
    }

    void hci_control_request_link_useless_bullshit(u8[] data) {
        u16 requested_connection_handle = data.read_le!u16(3);

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16)HciCommandOpcode.ReadRemoteSupportedFeatures)
        };
        send_hci_response(struct_to_bytes(status_response));
        
        HciReadRemoteFeaturesCompleteEvent features_response = {
            event_code: HciEventCode.ReadRemoteSupportedFeaturesComplete,
            parameter_length: 11,
            status: 0x00,
            connection_handle: requested_connection_handle,
            lmp_features: [0xbc, 0x02, 0x04, 0x38, 0x08, 0x00, 0x00, 0x00]
        };
        send_hci_response(struct_to_bytes(features_response));
    }

    void hci_control_request_link_change_packet_type(u8[] data) {
        u16 requested_connection_handle = data.read_le!u16(3);

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16) HciCommandOpcode.ChangeConnectionPacketType)
        };
        send_hci_response(struct_to_bytes(status_response));
        
        HciConnectionPacketTypeChangedEvent packet_response = {
            event_code: HciEventCode.ConnectionPacketTypeChanged,
            parameter_length: 5,
            status: 0x00,
            connection_handle: requested_connection_handle,
            packet_type: u16_le(0xcc18)
        };
        send_hci_response(struct_to_bytes(packet_response));
    }

    void hci_control_request_link_auth_complete(u8[] data) {
        u16 requested_connection_handle = data.read_le!u16(3);

        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16) HciCommandOpcode.AuthenticationRequested)
        };
        send_hci_response(struct_to_bytes(status_response));
        
        HciAuthenticationCompleteEvent auth_response = {
            event_code: HciEventCode.AuthenticationComplete,
            parameter_length: 3,
            status: 0x00,
            connection_handle: requested_connection_handle
        };
        send_hci_response(struct_to_bytes(auth_response));
    }

    void hci_control_request_link_policy_write_settings(u8[] data) {
        HciCommandStatusEvent status_response = {
            event_code: HciEventCode.CommandStatus,
            parameter_length: 4,
            status: 0x00,
            num_hci_command_packets: 1,
            command_opcode: u16_le(cast(u16) HciCommandOpcode.WriteLinkPolicySettings)
        };
        send_hci_response(struct_to_bytes(status_response));
    }

    void trivial_success(u8[] data) {
        send_hci_response(cast(u8[]) [0xe, data.length + 1, 0x01] ~ data);
    }

    void copy_to_user_buf(u32 user_buf_addr, u8[] data, size_t user_buf_len) {
        log_bluetooth("copy_to_user_buf: %x %s %x", user_buf_addr, data.to_hex_string, user_buf_len);
        if (data.length > user_buf_len) error_bluetooth("fuck");

        for (int i = 0; i < data.length; i++) {
            mem.physical_write_u8(user_buf_addr + i, data[i]);
        }
    }

    void update() {
        if (exists_disconnected_wiimote() && no_wiimotes_currently_connecting() && scanning) {
            import std.stdio;
            writefln("Sending connection request to wiimote");
            send_wiimote_connection_request(first_disconnected_wiimote());
        }

        if (!pending_acl.empty && acl_paddr != 0) {
            auto reply = pending_acl.front;
            pending_acl.removeFront();

            u32 acl_ioctl_vector = mem.physical_read_u32(acl_paddr + 0x18);
            log_bluetooth("pushing to acl paddr: %x", acl_ioctl_vector);
            log_bluetooth("queued acl response: %s", reply.to_hex_string);
            copy_to_user_buf(mem.physical_read_u32(acl_ioctl_vector + 16), reply,
                mem.physical_read_u32(acl_ioctl_vector + 20));
            ipc_response_queue.push_later(acl_paddr, cast(int) reply.length, 40_000);
            acl_paddr = 0;
        }

        if (!pending_hci.empty && hci_paddr != 0) {
            auto reply = pending_hci.front;
            pending_hci.removeFront();

            u32 hci_ioctl_vector = mem.physical_read_u32(hci_paddr + 0x18);
            log_bluetooth("pushing to hci paddr: %x", hci_ioctl_vector);
            log_bluetooth("queued hci response: %s", reply.to_hex_string);
            copy_to_user_buf(mem.physical_read_u32(hci_ioctl_vector + 16), reply,
                mem.physical_read_u32(hci_ioctl_vector + 20));
            ipc_response_queue.push_later(hci_paddr, cast(int) reply.length, 40_000);
            hci_paddr = 0;
        }
    }

    void send_wiimote_connection_request(Wiimote wiimote) {
        HciConnectionRequestEvent conn_request = {
            event_code: HciEventCode.ConnectionRequest,
            parameter_length: 10,
            bd_addr: wiimote.bd_addr,
            class_of_device: [0x00, 0x04, 0x48],
            link_type: 0x01
        };

        send_hci_response(struct_to_bytes(conn_request));
        wiimote.start_connecting();
    }

    void send_hci_response(u8[] data) {
        log_bluetooth("send_hci_response(%s)", data.to_hex_string);
        pending_hci ~= data;
    }

    void send_acl_response(u8[] data, size_t length) {
        import std.stdio;
        writefln("Device -> Remote: %s", data[0 .. length].to_hex_string);
        log_bluetooth("send_acl_response(%s)", data.to_hex_string);
        pending_acl ~= data[0 .. length];
        update();
    }
}
