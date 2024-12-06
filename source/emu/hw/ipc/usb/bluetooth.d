// module emu.hw.ipc.usb.bluetooth;

// import emu.hw.ipc.ipc;
// import emu.hw.memory.strategy.memstrategy;
// import util.number;
// import util.log;

// struct HciEvt {
//     u8 evt_code;
//     u8 len;
// }

// enum Direction {
//     HostToController = 0,
//     ControllerToHost = 1,
// }

// final class Bluetooth {
//     u8[] hci_buffer;

//     u32 hci_paddr = 0;
//     u32 acl_paddr = 0;

//     u8[3] call_of_duty;

//     IPCResponseQueue ipc_response_queue;
//     this(IPCResponseQueue response_queue) {
//         this.ipc_response_queue = response_queue;
//     }

//     Mem mem;
//     void connect_mem(Mem mem) {
//         this.mem = mem;
//     }

//     u8[] hci_request(Direction direction, u32 paddr, u8[] data) {
//         log_bluetooth("HCI request: %s", data);
//         if (direction == Direction.ControllerToHost) {
//             log_bluetooth("Setting hci paddr: %x", paddr);
//             hci_paddr = paddr;
//             // log_bluetooth("HCI return: %x", hci_buffer.length);
//             // return hci_buffer;
//         } 
//         // unsure

//         for (int i = 0; i < data.length; i += 16) {
//             import std.algorithm;
//             // log_bluetooth("HCI request: %d: %s", i, data[i..min(i + 16, data.length)]);
//         }

//         log_bluetooth("HCI request: %x", data.length);


//         // u8[] acl_data = new u8[data.length];
//         // for (int i = 0; i < data.length; i += 2) {
//         //     acl_data[i]     = 0xe;
//         //     acl_data[i + 1] = 0x01;
//         // }

//         return [];
//     }

//     u8[] acl_request(u32 paddr, u8[] data) {
//         log_bluetooth("ACL request: %x", data.length);

//         acl_paddr = paddr;
//         // u8[] acl_data = new u8[data.length];
//         // for (int i = 0; i < data.length; i += 2) {
//         //     acl_data[i]     = 0xe;
//         //     acl_data[i + 1] = 0x01;
//         // }

//         return [];
//     }

//     u8[] hci_control_request(u32 paddr, u8[] data) {
//         log_bluetooth("HCI control request: %s", data);

//         if (data.length < 3) {
//             return [];
//         }

//         auto ogf = data[1] >> 2;
//         auto ocf = ((data[1] & 0x03) << 8) | data[0];
//         log_bluetooth("HCI control request: ogf=%d ocf=%04x", ogf, ocf);

//         switch (ogf) {
//             case 0x03: hci_control_request_baseband(ocf, data); break;
//             case 0x04: hci_control_request_informational(ocf, data[2..$]); break;
//             case 0x3f: hci_control_request_vendor(ocf, data[2..$]); break;
//             default: error_bluetooth("unimplemented HCI control request: ogf=%d ocf=%04x", ogf, ocf);
//         }

//         // is this correct? legitimately what the fuck is going on anymore

//         if (hci_paddr != 0) {
//             u32 hci_ioctl_vector = mem.paddr_read_u32(hci_paddr + 0x18);
//             log_bluetooth("pushing to hci paddr: %x", hci_ioctl_vector);
//             log_bluetooth("hci resopnse: %s", hci_buffer);
//             copy_to_user_buf(mem.paddr_read_u32(hci_ioctl_vector + 16), hci_buffer,
//                 mem.paddr_read_u32(hci_ioctl_vector + 20));
//             // mem.paddr_write_u32(hci_ioctl_vector + 20, cast(u32) hci_buffer.length);
//             ipc_response_queue.push_later(hci_paddr, cast(int) hci_buffer.length, 40_000);
//             hci_buffer = [];
//         }

//         // if (acl_paddr != 0) {
//             // log_bluetooth("pushing to acl paddr");
//             // copy_to_user_buf(mem.paddr_read_u8(mem.paddr_read_u32(acl_paddr + 16)), hci_buffer,
//                 // mem.paddr_read_u32(mem.paddr_read_u32(acl_paddr + 20)));
//             // ipc_response_queue.push_later(acl_paddr, cast(int) hci_buffer.length, 40_000);
//         // }

//         u32 ioctl_vector = mem.paddr_read_u32(paddr + 0x18);
//         log_bluetooth("pushing to paddr: %x", ioctl_vector);
//         // copy_to_user_buf(mem.paddr_read_u32(ioctl_vector + 48), hci_buffer[3..$],
//             // mem.paddr_read_u32(ioctl_vector + 52));
//         // mem.paddr_write_u32(ioctl_vector + 52, cast(u32) hci_buffer[3..$].length);
//         ipc_response_queue.push_later(paddr, cast(int)  mem.paddr_read_u32(ioctl_vector + 52), 40_000);

//         return [];
//     }

//     u8[] hci_control_request_vendor(int ocf, u8[] data) {
//         switch (ocf) {
//             case 0x4c: return hci_control_request_vendor_who_knows(data);
//             case 0x4f: return hci_control_request_vendor_who_cares(data);
//             default: error_bluetooth("unimplemented HCI control vendor request: ocf=%04x", ocf);
//         }

//         return [];
//     }

//     // 45 47 43 24 18 
//     u8[] hci_control_request_baseband(int ocf, u8[] data) {
//         switch (ocf) {
//             case 0x003: return trivial_success(data); // reset
//             case 0x00a: return hci_control_request_baseband_write_pin_type(data);
//             case 0x00d: return hci_control_request_baseband_write_link_policy(data);
//             case 0x013: return hci_control_request_write_local_name(data);
//             case 0x018: return hci_control_request_baseband_write_page_timeout(data);
//             case 0x024: return hci_control_request_baseband_write_call_of_duty(data);
//             case 0x033: return hci_control_request_baseband_host_buffer_size(data);
//             case 0x043: return hci_control_request_baseband_write_inquiry_scan_type(data);
//             case 0x045: return hci_control_request_baseband_write_inquiry_mode(data);
//             case 0x047: return hci_control_request_baseband_write_page_scan_type(data);
//             default: error_bluetooth("unimplemented HCI control baseband request: ocf=%04x", ocf);
//         }

//         return [];
//     }

//     u8[] hci_control_request_informational(int ocf, u8[] data) {
//         switch (ocf) {
//             case 0x001: return hci_control_request_informational_read_local_version(data);
//             case 0x003: return hci_control_request_informational_read_local_features(data);
//             case 0x005: return hci_control_request_informational_read_buffer_size(data);
//             case 0x009: return hci_control_request_informational_read_bd_addr(data);
//             default: error_bluetooth("unimplemented HCI control informational request: ocf=%04x", ocf);
//         }

//         return [];
//     }

//     u8[] hci_control_request_baseband_write_call_of_duty(u8[] data) {
//         call_of_duty = data[2..5];
//         log_bluetooth("HCI control request: baseband write call of duty");

//         return trivial_success(data);
//     }

//     u8[] hci_control_request_write_local_name(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x13, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: write local name");

//         return response;
//     }

//     u8[] hci_control_request_informational_read_buffer_size(u8[] data) {
//         u8[] response = [0xe, 0x0b, 0x01, 0x05, 0x10, 0x00, 0x53, 0x01, 0x40, 0x0a, 0x00, 0x00, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: informational read buffer size");

//         return response;
//     }

//     u8[] hci_control_request_baseband_write_pin_type(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x0a, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband write pin type");

//         return response;
//     }

//     u8[] hci_control_request_baseband_host_buffer_size(u8[] data) {
//         u8[] response = [0xe, 0x0c, 0x01, 0x33, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband host buffer size");

//         return response;
//     }

//     u8[] hci_control_request_informational_read_local_version(u8[] data) {
//         u8[] response = [0xe, 0x0c, 0x01, 0x01, 0x10, 0x00, 0x03, 0xa7, 0x40, 0x03, 0x0f, 0x00, 0x0e, 0x43];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: informational read local version");

//         return response;
//     }

//     u8[] hci_control_request_informational_read_local_features(u8[] data) {
//         u8[] response = [0xe, 0x0c, 0x01, 0x03, 0x10, 0x00, 0xff, 0xff, 0x8d, 0xfe, 0x9b, 0xf9, 0x00, 0x80];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: informational read local features");

//         return response;
//     }

//     u8[] hci_control_request_informational_read_bd_addr(u8[] data) {
//         u8[] response = [0xe, 0x0c, 0x01, 0x09, 0x10, 0x00, 0x11, 0x02, 0x19, 0x79, 0x00, 0xff];
//         hci_buffer ~= response;

//         log_bluetooth("HCI control request: informational read bd addr");

//         return response;
//     }

//     u8[] hci_control_request_baseband_write_page_timeout(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x18, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband write page timeout");

//         return response;
//     }

//     u8[] hci_control_request_baseband_write_inquiry_scan_type(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x43, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband write inquiry scan type");

//         return response;
//     }

//     u8[] hci_control_request_baseband_write_inquiry_mode(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x45, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband write inquiry mode");

//         return response;
//     }

//     u8[] hci_control_request_baseband_write_page_scan_type(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x47, 0x0c, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband write page scan type");

//         return response;
//     }

//     u8[] hci_control_request_baseband_write_link_policy(u8[] data) {
//         u8[] response = [0xe, 0x08, 0x01, 0x0d, 0x0c, 0x00, 0xff, 0x00, 0x05, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: baseband write link policy");

//         return response;
//     }

//     u8[] hci_control_request_vendor_who_knows(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x4c, 0xfc, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: vendor who knows");

//         return response;
//     }

//     u8[] hci_control_request_vendor_who_cares(u8[] data) {
//         u8[] response = [0xe, 0x04, 0x01, 0x4c, 0xfc, 0x00];
//         hci_buffer ~= response;
//         log_bluetooth("HCI control request: vendor who cares");

//         return response;
//     }

//     u8[] trivial_success(u8[] data) {
//         u8[] response = cast(u8[]) [0xe, data.length + 1, 0x01] ~ data;
//         hci_buffer ~= response;

//         log_bluetooth("Trivial success: %s", response);
//         log_bluetooth("Trivial success: %s", hci_buffer);
//         log_bluetooth("HCI control request: success");

//         return response;
//     }

//     void copy_to_user_buf(u32 user_buf_addr, u8[] data, size_t user_buf_len) {
//         log_bluetooth("copy_to_user_buf: %x %s %x", user_buf_addr, data, user_buf_len);
//         if (data.length > user_buf_len) error_bluetooth("fuck");

//         for (int i = 0; i < data.length; i++) {
//             mem.paddr_write_u8(user_buf_addr + i, data[i]);
//         }
//     }
// }