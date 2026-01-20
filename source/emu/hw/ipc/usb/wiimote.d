module emu.hw.ipc.usb.wiimote;

import emu.hw.ipc.usb.bluetooth;
import emu.hw.ipc.usb.bluetooth_types;
import emu.hw.ipc.usb.extensions.extension;
import emu.hw.ipc.usb.extensions.nunchuk;
import emu.hw.ipc.usb.l2cap;
import emu.hw.ipc.usb.extensions.extension;
import emu.scheduler;
import std.algorithm;
import std.random;
import core.stdc.string : memcpy;
import util.array;
import util.bitop;
import util.endian;
import util.force_cast;
import util.log;
import util.number;

enum WiimoteState {
    Disconnected,
    Connecting,
    Connected,
}

enum WiimoteButton {
    Two = 0x01,
    One = 0x02,
    B = 0x04,
    A = 0x08,
    Minus = 0x10,
    Home = 0x80,
    Left = 0x100,
    Right = 0x200,
    Down = 0x200,
    Up = 0x400,
    Plus = 0x800,
}

final class Wiimote {
    WiimoteState state;
    Bluetooth bluetooth;

    u8[0x1700] ram;

    u8 reporting_mode;
    ContinuousMode continuous_mode;

    int[] channels_to_initialize = [];

    Scheduler scheduler;
    ulong send_continuous_data_report_event_id;

    int leds;
    bool camera_enable_pin1 = false;
    bool camera_enable_pin2 = false;
    
    auto rnd = Random(42);

    u16 button_state = 0;
    u8[3] accelerometer;

    u8[6] bd_addr;
    u16 connection_handle;
    int num_acl_packets_processed;

    struct IrDot {
        u16 x;
        u16 y;
        bool valid;
    }

    enum L2capChannelBindingState {
        Unbound,
        Connecting,
        Bound,
    }

    struct L2capChannelBinding {
        // All bindings start as unbound. When we send a ConnectReq, they go to Connecting.
        // When we receive a ConnectRsp, they go to Bound.

        L2capChannelBindingState state;

        u16 source_channel;
        u16 dest_channel;
        PSM psm;
    }

    L2capChannelBinding[2] l2cap_channel_bindings;

    L2capChannelBinding get_next_unbound_channel_binding() {
        foreach (ref binding; l2cap_channel_bindings) {
            if (binding.state == L2capChannelBindingState.Unbound) {
                return binding;
            }
        }

        error_wiimote("No unbound L2CAP channel bindings available");
    }

    bool all_channel_bindings_bound() {
        foreach (ref binding; l2cap_channel_bindings) {
            if (binding.state != L2capChannelBindingState.Bound) {
                return false;
            }
        }

        return true;
    }

    IrDot[2] ir_dots; 

    WiimoteExtension extension;
    
    void connect_extension(WiimoteExtensionType extension_type) {
        this.extension = create_extension(extension_type);
    }

    void disconnect_extension() {
        this.extension = null;
    }

    bool is_extension_connected() {
        return extension !is null;
    }

    @property camera_enabled() {
        return camera_enable_pin1 && camera_enable_pin2;
    }

    this() {
        state = WiimoteState.Disconnected;

        reporting_mode = 0x30;
        continuous_mode = ContinuousMode.Continuous;

        this.ram[0..42] = [
            0x7f, 0x5d, 0x03, 0x80, 0x5d, 0x80, 0xa2, 0xb8, 0x7f, 0xa2, 0x0c, 
            0x7f, 0x5d, 0x03, 0x80, 0x5d, 0x80, 0xa2, 0xb8, 0x7f, 0xa2, 0x0c, 
            0x80, 0x80, 0x80, 0x00, 0x9a, 0x9a, 0x9a, 0x00, 0x00, 0xa3, 
            0x80, 0x80, 0x80, 0x00, 0x9a, 0x9a, 0x9a, 0x00, 0x00, 0xa3, 
        ];

        num_acl_packets_processed = 0;

        l2cap_channel_bindings = [
            L2capChannelBinding(
                state: L2capChannelBindingState.Unbound,
                source_channel: Channel.HIDControl,
                dest_channel: 0,
                psm: PSM.Control
            ),

            L2capChannelBinding(
                state: L2capChannelBindingState.Unbound,
                source_channel: Channel.HIDInterrupt,
                dest_channel: 0,
                psm: PSM.Interrupt
            )
        ];
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_bluetooth(Bluetooth bluetooth) {
        this.bluetooth = bluetooth;
    }

    void enable_data_reporting() {
        send_continuous_data_report_event_id = scheduler.add_event_relative_to_self(&send_continuous_data_report, 1_000_000);
    }

    void send_continuous_data_report() {
        log_wiimote("Sending continuous data report");

        send_data_report();
        send_continuous_data_report_event_id = scheduler.add_event_relative_to_self(&send_continuous_data_report, 1_000_000);
    }

    void start_connecting() {
        import std.stdio;
        writefln("Starting Wiimote connection");
        state = WiimoteState.Connecting;   
    }

    void finish_connecting() {
        // The remote has accepted our connection. Now we need to configure L2CAP channels.
        // There's two PSMs we need to configure: Control (0x11) and Interrupt (0x13).
        // Each PSM is configured by sending a ConnectReq signal. After the remote sends a 
        // ConnectRsp, both sides exchange ConfigReq/ConfigRsp on the signalling channel: 
        // we acknowledge their ConfigReq with success, MTU 0x0280 and a flush timeout of 
        // 0xffff, then immediately send our own ConfigReq advertising the smaller 0x00b9 
        // MTU real Wiimotes use. Once Control config is acknowledged we kick off the 
        // Interrupt channel and repeat the config dance.

        state = WiimoteState.Connected;
        setup_channel_binding(get_next_unbound_channel_binding());
    }

    bool is_connecting() {
        return state == WiimoteState.Connecting;
    }

    bool is_connected() {
        return state == WiimoteState.Connected;
    }

    bool is_disconnected() {
        return state == WiimoteState.Disconnected;
    }

    u8 current_identifier = 1;
    u8 fresh_identifier() {
        return current_identifier++;
    }

    void setup_channel_binding(L2capChannelBinding channel_binding) {
        AclPacket acl_packet = AclPacket(
            handle_and_flags: (connection_handle & 0x0FFF) | AclFlags.PbFirstNonFlushable,
            data_total_length: 12,
            l2cap_command: WiimoteL2capCommand(
                header: L2capCommandHeader(
                    length: 8,
                    Channel.Signal,
                ),
                signal: L2capSignalCommand(
                    header: L2capSignalHeader(
                        signal_type: SignalType.ConnectReq,
                        identifier: fresh_identifier(),
                        length: 4
                    ),
                    connection_req: L2capConnectionReq(
                        psm: channel_binding.psm,
                        source_channel: channel_binding.source_channel
                    )
                )
            )
        );

        bluetooth.send_acl_response(struct_to_bytes(acl_packet), 16);
    }

    void handle_l2cap(u8[] data) {
        num_acl_packets_processed++;

        WiimoteL2capCommand* l2cap_command = cast(WiimoteL2capCommand*) data.ptr;

        final switch (l2cap_command.header.channel) {
            case Channel.Signal:       handle_l2cap_signal(l2cap_command); break;
            case Channel.HIDControl:   error_wiimote("L2CAP HID Control not implemented"); break;
            case Channel.HIDInterrupt: handle_l2cap_hid(l2cap_command.hid_interrupt); break;
        }
    }

    void handle_l2cap_signal(WiimoteL2capCommand* l2cap_command) {
        L2capSignalCommand* command = &l2cap_command.signal;

        final switch (command.header.signal_type) {
            case SignalType.ConnectReq:    error_wiimote("L2CAP_CONNECT_REQ not implemented"); break;
            case SignalType.ConnectRsp:    handle_l2cap_connect_rsp(command.connection_rsp); break;
            case SignalType.ConfigReq:     handle_l2cap_config_req(command); break;
            case SignalType.ConfigRsp:     handle_l2cap_config_rsp(); break;
            case SignalType.DisconnectReq: error_wiimote("L2CAP_DISCONNECT_REQ not implemented"); break;
        }
    }

    void handle_l2cap_connect_rsp(L2capConnectionRsp connection_rsp) {
        L2capChannelBinding* binding = find_binding_by_source_channel(connection_rsp.source_channel);

        if (!binding) {
            error_wiimote("Unknown channel in ConnectRsp: %x", connection_rsp.source_channel);
            return;
        }

        binding.dest_channel = connection_rsp.dest_channel;
        binding.state        = L2capChannelBindingState.Bound;

        send_config_req(binding.dest_channel);
    }

    L2capChannelBinding* find_binding_by_source_channel(u16 source_channel) {
        foreach (ref binding; l2cap_channel_bindings) {
            if (binding.source_channel == source_channel) {
                return &binding;
            }
        }

        return null;
    }

    void handle_l2cap_config_req(L2capSignalCommand* command) {
        L2capConfigReq* config_req = &command.config_req;
        size_t options_length = command.header.length - L2capConfigReq.sizeof;
        u8* config_options = (cast(u8*) config_req) + L2capConfigReq.sizeof;

        send_config_rsp(config_req, command.header.identifier, config_options, options_length);
    }

    void send_config_rsp(L2capConfigReq* config_req, u8 incoming_identifier, u8* config_options, size_t options_length) {
        size_t config_rsp_options_size = options_length;
        size_t l2cap_payload_length = L2capSignalHeader.sizeof + L2capConfigRsp.sizeof + config_rsp_options_size;
        size_t data_total_length = l2cap_payload_length + L2capCommandHeader.sizeof;
        size_t acl_packet_size = data_total_length + 4;

        AclPacket acl_packet = AclPacket(
            handle_and_flags: (connection_handle & 0x0FFF) | AclFlags.PbFirstNonFlushable,
            data_total_length: cast(u16) data_total_length,
            l2cap_command: WiimoteL2capCommand(
                header: L2capCommandHeader(
                    length: cast(u16) l2cap_payload_length,
                    Channel.Signal,
                ),
                signal: L2capSignalCommand(
                    header: L2capSignalHeader(
                        signal_type: SignalType.ConfigRsp,
                        identifier: incoming_identifier,
                        length: cast(u16) (L2capConfigRsp.sizeof + config_rsp_options_size)
                    ),
                    config_rsp: L2capConfigRsp(
                        channel: find_binding_by_source_channel(config_req.channel).dest_channel,
                        flags: 0,
                        result: 0
                    )
                )
            )
        );

        u8[] config_rsp_data = new u8[acl_packet_size];
        memcpy(&config_rsp_data[0], &acl_packet, data_total_length);

        size_t rsp_options_offset = acl_packet_size - config_rsp_options_size;
        memcpy(&config_rsp_data[rsp_options_offset], config_options, config_rsp_options_size);

        bluetooth.send_acl_response(config_rsp_data, acl_packet_size);
    }

    void send_config_req(u16 channel) {
        L2capConfigOption[] config_req_options = [
            L2capConfigOption(
                header: L2capConfigOptionHeader(
                    option_type: L2capConfigOptionType.MTU,
                    length: L2capConfigOptionMtu.sizeof
                ),
                mtu: L2capConfigOptionMtu(0x00b9)
            )
        ];

        size_t config_req_options_size = config_req_options.length * L2capConfigOption.sizeof;
        size_t l2cap_payload_length = L2capSignalHeader.sizeof + L2capConfigReq.sizeof + config_req_options_size;
        size_t data_total_length = l2cap_payload_length + L2capCommandHeader.sizeof;
        size_t total_size = data_total_length + config_req_options_size;
        size_t acl_packet_size = data_total_length + 4;

        AclPacket acl_packet = AclPacket(
            handle_and_flags: (connection_handle & 0x0FFF) | AclFlags.PbFirstNonFlushable,
            data_total_length: cast(u16) data_total_length,
            l2cap_command: WiimoteL2capCommand(
                header: L2capCommandHeader(
                    length: cast(u16) l2cap_payload_length,
                    Channel.Signal,
                ),
                signal: L2capSignalCommand(
                    header: L2capSignalHeader(
                        signal_type: SignalType.ConfigReq,
                        identifier: fresh_identifier(),
                        length: cast(u16) (L2capConfigReq.sizeof + config_req_options_size)
                    ),
                    config_req: L2capConfigReq(
                        channel: channel,
                        flags: 0
                    )
                )
            )
        );

        u8[] config_req_data = new u8[acl_packet_size];
        memcpy(&config_req_data[0], &acl_packet, data_total_length);

        size_t req_options_offset = acl_packet_size - config_req_options_size;
        u8* req_options_ptr = cast(u8*) config_req_options.ptr;
        memcpy(&config_req_data[req_options_offset], req_options_ptr, config_req_options_size);

        bluetooth.send_acl_response(config_req_data, acl_packet_size);
    }

    void handle_l2cap_config_rsp() {
        if (all_channel_bindings_bound()) {
            enable_data_reporting();
        } else {
            setup_channel_binding(get_next_unbound_channel_binding());
        }
    }

    void handle_l2cap_hid(WiimoteHidInterruptPayload l2cap_payload) {
        final switch (l2cap_payload.report_direction) {
            case ReportDirection.Input:  handle_input_report (l2cap_payload.input_report);  break;
            case ReportDirection.Output: handle_output_report(l2cap_payload.output_report); break;
        }
    }

    void handle_input_report(InputReport input_report) {
        error_wiimote("Input report not allowed");
    }

    void handle_output_report(OutputReport output_report) {
        switch (output_report.report_id) {
            case OutputReportId.RumbleReport:             handle_rumble                    (output_report.rumble_report);              break;
            case OutputReportId.PlayerLEDs:               handle_player_leds               (output_report.player_leds);                break;
            case OutputReportId.DataReportingMode:        handle_data_reporting_mode       (output_report.data_reporting_mode);        break;
            case OutputReportId.IRCameraEnable:           handle_ir_camera_enable          (output_report.ir_camera_enable);           break;
            case OutputReportId.SpeakerEnable:            handle_speaker_enable            (output_report.speaker_enable);             break;
            case OutputReportId.SpeakerMute:              handle_speaker_mute              (output_report.speaker_mute);               break;
            case OutputReportId.StatusInformationRequest: handle_status_information_request(output_report.status_information_request); break;
            case OutputReportId.ReadMemoryAndRegisters:   handle_read_memory_and_registers (output_report.read_memory_and_registers);  break;
            case OutputReportId.WriteMemoryAndRegisters:  handle_write_memory_and_registers(output_report.write_memory_and_registers); break;
            case OutputReportId.IRCameraEnable2:          handle_ir_camera_enable2         (output_report.ir_camera_enable2);          break; 
            case OutputReportId.SpeakerData:              handle_speaker_data              (output_report.speaker_data);               break;
        
            default: error_wiimote("Output report not implemented: %s", output_report.report_id); break;
        }
    }

    void handle_player_leds(PlayerLEDs report) {
        this.leds = report.led_status >> 4;
        trivial_success(OutputReportId.PlayerLEDs);
    }

    void handle_read_memory_and_registers(ReadMemoryAndRegistersReport report) {
        u32 address = 
            (report.address[0] << 16) |
            (report.address[1] <<  8) |
            (report.address[2] <<  0);
        
        log_wiimote("Read memory and registers: %x", address);

        final switch (report.address_space & 4) {
            case AddressSpace.Memory:     return handle_read_memory   (address, cast(u16) report.size);
            case AddressSpace.Registers1: 
            case AddressSpace.Registers2: return handle_read_registers(address, cast(u16) report.size);
        }
    }

    void handle_read_memory(u32 address, u16 size) {
        if (address >= ram.length || address + size > ram.length) {
            ReadMemoryAndRegistersData result2;
            fill_button_state(&result2);
            result2.size_and_error = 0xf8;
            result2.data_offset = u16_be(cast(u16) address);
            send_input_report_response(InputReport(InputReportId.ReadMemoryAndRegistersData, read_memory_and_registers_data : result2), ReadMemoryAndRegistersData.sizeof);
        } else {
            int read = 0;

            while (read < size) {
                ReadMemoryAndRegistersData result;
                fill_button_state(&result);
                u8 read_this_time = cast(u8) min(size - read, 16);

                result.size_and_error = cast(u8) ((read_this_time - 1) << 4);
                result.data_offset = u16_be(cast(u16) (address + read));
                
                result.data[0 .. read_this_time] = ram[address + read .. address + read + read_this_time];
                    
                read += read_this_time;

                send_input_report_response(InputReport(InputReportId.ReadMemoryAndRegistersData, read_memory_and_registers_data : result), ReadMemoryAndRegistersData.sizeof);
            }         
        }
    }

    void handle_read_registers(u32 address, u16 size) {
        if (extension && address == 0xA400FA && size == 6) {
            ReadMemoryAndRegistersData result;
            fill_button_state(&result);

            result.size_and_error = 0x50; // 6 bytes -> (6 - 1) << 4
            result.data_offset = u16_be(cast(u16) address);
            result.data[0 .. 6] = extension.get_id();

            send_input_report_response(InputReport(InputReportId.ReadMemoryAndRegistersData, read_memory_and_registers_data : result), ReadMemoryAndRegistersData.sizeof);
            return;
        }

        if (extension && address == 0xA40020 && size == 32) {
            ReadMemoryAndRegistersData result;
            fill_button_state(&result);

            result.size_and_error = 0xf0; // 16 bytes -> (16 - 1) << 4
            result.data_offset = u16_be(cast(u16) address);
            result.data[0 .. 8] = [0, 0, 0, 0, 0, 0, 0, 0];
            send_input_report_response(InputReport(InputReportId.ReadMemoryAndRegistersData, read_memory_and_registers_data : result), ReadMemoryAndRegistersData.sizeof);
            
            result.size_and_error = 0xf0; // 16 bytes -> (16 - 1) << 4
            result.data_offset = u16_be(cast(u16) (address + 16));
            result.data[0 .. 8] = [0, 0, 0, 0, 0, 0, 0, 0];
            send_input_report_response(InputReport(InputReportId.ReadMemoryAndRegistersData, read_memory_and_registers_data : result), ReadMemoryAndRegistersData.sizeof);
            return;
        }

        error_wiimote("Read registers not implemented : %x, size: %d", address, size);
    }

    void handle_write_memory_and_registers(WriteMemoryAndRegistersReport report) {
        u32 address = 
            (report.address[0] << 16) |
            (report.address[1] <<  8) |
            (report.address[2] <<  0);

        log_wiimote("Write memory and registers: %x", address);

        final switch (report.address_space & 4) {
            case AddressSpace.Memory:     return handle_write_memory   (address, cast(u16) report.size, report.data);
            case AddressSpace.Registers1: 
            case AddressSpace.Registers2: return handle_write_registers(address, cast(u16) report.size, report.data);
        }
    }

    void handle_write_memory(u32 address, u16 size, u8[] data) {
        error_wiimote("Write memory not implemented");
    }

    void handle_write_registers(u32 address, u16 size, u8[] data) {
        if (address.bits(20, 23) == 0xb) {
            // speaker shit
            trivial_success(OutputReportId.WriteMemoryAndRegisters);
            return;
        }

        switch (address) {
            case 0xa20009: // speaker init part 1
                break;
            
            case 0xa20001: // speaker init part 2
                break;
            
            case 0xa20008: // speaker init part 3
                break;
            
            case 0xa400f0: // controller extension init part 1
                break;
            
            case 0xa400fb: // controller extension init part 2
                break;
            
            case 0xa40040: // controller extension init part 3
                break;
            
            case 0xa40046: // controller extension init part 4
                break;
            
            case 0xa4004c: // controller extension init part 5
                break;
            
            case 0xa40020: // controller extension init part 6
                break;
            
            default: 
                error_wiimote("Write registers not implemented: %x %s", address, data);
        }

        trivial_success(OutputReportId.WriteMemoryAndRegisters);
    }

    void handle_data_reporting_mode(DataReportingMode report) {
        log_wiimote("Data reporting mode: %s", report);
        this.continuous_mode = cast(ContinuousMode) (report.continuous_mode & 0x40);
        this.reporting_mode  = report.report_mode;

        if (this.reporting_mode.bits(4, 7) != 0x3) {
            error_wiimote("Data reporting mode is not 0x30 - 0x3f (%x)", this.reporting_mode);
        }

        trivial_success(OutputReportId.DataReportingMode);
    }

    void handle_speaker_enable(SpeakerEnableReport report) {
        SpeakerEnablement enablement = cast(SpeakerEnablement) (report.speaker_enablement & 4);
        
        if (enablement == SpeakerEnablement.Enabled) {
            log_wiimote("Speaker enabled");
        } else {
            log_wiimote("Speaker disabled");
        }

        trivial_success(OutputReportId.SpeakerEnable);
    }

    void handle_speaker_mute(SpeakerMuteReport report) {
        SpeakerMute mute = cast(SpeakerMute) (report.speaker_mute & 4);
        
        if (mute == SpeakerMute.Mute) {
            log_wiimote("Speaker muted");
        } else {
            log_wiimote("Speaker unmuted");
        }

        trivial_success(OutputReportId.SpeakerMute);
    }

    void handle_status_information_request(StatusInformationRequestReport report) {
        StatusInformationReport response;
        fill_button_state(&response);

        response.led_and_flags = cast(u8) ((leds << 4) | (camera_enabled << 3) | (is_extension_connected() << 1));
        response.battery_level = cast(u8) (100);

        send_input_report_response(InputReport(InputReportId.StatusInformation, status_information_report : response), StatusInformationReport.sizeof);
    }

    void handle_ir_camera_enable(IRCameraEnable report) {
        camera_enable_pin1 = report.ir_camera_state == IRCameraState.On;

        trivial_success(OutputReportId.IRCameraEnable);
    }

    void handle_ir_camera_enable2(IRCameraEnable2 report) {
        camera_enable_pin2 = report.ir_camera_state == IRCameraState.On;

        trivial_success(OutputReportId.IRCameraEnable2);
    }

    void handle_rumble(RumbleReport report) {
        log_wiimote("RumbleReport: %s", report.rumble ? "On" : "Off");

        trivial_success(OutputReportId.RumbleReport);
    }

    void handle_speaker_data(SpeakerData report) {
        trivial_success(OutputReportId.SpeakerData);
    }

    void fill_button_state(T)(T* result) {
        result.button_state[0] = button_state >> 8;
        result.button_state[1] = button_state & 0xff;
    }

    void fill_accelerometer_state(T)(T* result) {
        result.accelerometer[0] = accelerometer[0];
        result.accelerometer[1] = accelerometer[1];
        result.accelerometer[2] = accelerometer[2];
    }

    void trivial_success(OutputReportId report_id) {
        AcknowledgeOutputReport result;
        fill_button_state(&result);

        result.report_id = report_id;
        result.error_code = 0;

        send_input_report_response(InputReport(InputReportId.AcknowledgeOutputReport, acknowledge_output_report : result), AcknowledgeOutputReport.sizeof);
    }

    void send_input_report_response(InputReport input_report, size_t report_size) {
        size_t l2cap_payload_length = report_size + 2; // ReportDirection + ReportId
        size_t data_total_length = l2cap_payload_length + L2capCommandHeader.sizeof;

        log_wiimote("Sending input report response: %x", input_report.acknowledge_output_report.report_id);

        AclPacket acl_packet = AclPacket(
            handle_and_flags: (connection_handle & 0x0FFF) | AclFlags.PbFirstNonFlushable,
            data_total_length: cast(u16) data_total_length,
            l2cap_command: WiimoteL2capCommand(
                header: L2capCommandHeader(
                    length: cast(u16) l2cap_payload_length, 
                    channel: find_binding_by_source_channel(Channel.HIDInterrupt).dest_channel
                ),
                hid_interrupt: WiimoteHidInterruptPayload(
                    report_direction: ReportDirection.Input,
                    input_report: input_report
                )
            )
        );

        bluetooth.send_acl_response(struct_to_bytes(acl_packet), data_total_length + 4);
    }

    private u16 clamp_ir_x(int x) {
        return cast(u16) clamp(x, 0, 1023);
    }

    private u16 clamp_ir_y(int y) {
        return cast(u16) clamp(y, 0, 767);
    }

    private void fill_ir_basic(ref ubyte[10] dest) {
        u16 x1 = ir_dots[0].valid ? clamp_ir_x(ir_dots[0].x) : 0x3ff;
        u16 y1 = ir_dots[0].valid ? clamp_ir_y(ir_dots[0].y) : 0x3ff;
        u16 x2 = ir_dots[1].valid ? clamp_ir_x(ir_dots[1].x) : 0x3ff;
        u16 y2 = ir_dots[1].valid ? clamp_ir_y(ir_dots[1].y) : 0x3ff;

        dest[0] = cast(ubyte) (x1 & 0xff);
        dest[1] = cast(ubyte) (y1 & 0xff);
        dest[2] = cast(ubyte) (((y1 >> 8) & 0x3) << 6 |
                               ((x1 >> 8) & 0x3) << 4 |
                               ((y2 >> 8) & 0x3) << 2 |
                               ((x2 >> 8) & 0x3));
        dest[3] = cast(ubyte) (x2 & 0xff);
        dest[4] = cast(ubyte) (y2 & 0xff);

        dest[5 .. 10] = 0xff;

        log_wiimote("Filled dest: %s", dest);
    }

    void set_screen_position(int screen_x, int screen_y, int screen_width, int screen_height) {
        log_wiimote("Setting screen position: %d, %d (screen size: %d, %d)", screen_x, screen_y, screen_width, screen_height);

        float nx = clamp(cast(float) screen_x / cast(float) (screen_width - 1), 0.0f, 1.0f);
        float ny = clamp(cast(float) screen_y / cast(float) (screen_height - 1), 0.0f, 1.0f);

        // collected from a stupid test rom
        enum DOT0_X_MIN = 174;
        enum DOT0_X_MAX = 707;
        enum DOT1_X_MIN = 318;
        enum DOT1_X_MAX = 850;
        enum DOT_Y_MIN  = 280;
        enum DOT_Y_MAX  = 688;

        int dot0_x = cast(int) (DOT0_X_MIN + nx * (DOT0_X_MAX - DOT0_X_MIN) + 0.5f);
        int dot1_x = cast(int) (DOT1_X_MIN + nx * (DOT1_X_MAX - DOT1_X_MIN) + 0.5f);
        int dot_y  = cast(int) (DOT_Y_MIN  + ny * (DOT_Y_MAX  - DOT_Y_MIN) + 0.5f);

        ir_dots[0] = IrDot(clamp_ir_x(dot0_x), clamp_ir_y(dot_y), true);
        ir_dots[1] = IrDot(clamp_ir_x(dot1_x), clamp_ir_y(dot_y), true);
    }

    void send_data_report() {
        log_wiimote("Sending data report: %x", reporting_mode);

        switch (reporting_mode) {
            case 0x30:
                DataReport30 data_report;
                fill_button_state(&data_report);
                send_input_report_response(InputReport(InputReportId.DataReport30, data_report_30 : data_report), DataReport30.sizeof);
                break;
            
            case 0x31:
                DataReport31 data_report31;
                fill_button_state(&data_report31);
                fill_accelerometer_state(&data_report31);
                send_input_report_response(InputReport(InputReportId.DataReport31, data_report_31 : data_report31), DataReport31.sizeof);
                break;
            
            case 0x33:
                DataReport33 data_report;
                fill_button_state(&data_report);
                fill_accelerometer_state(&data_report);
                send_input_report_response(InputReport(InputReportId.DataReport33, data_report_33 : data_report), DataReport33.sizeof);
                break;

            case 0x37:
                assert_wiimote(extension !is null, "Data report 0x37 requested with no extension connected");

                DataReport37 data_report37;
                fill_button_state(&data_report37);
                fill_accelerometer_state(&data_report37);
                fill_ir_basic(data_report37.ir_camera);

                data_report37.extension[] = extension.get_report_data();

                send_input_report_response(InputReport(InputReportId.DataReport37, data_report_37 : data_report37), DataReport37.sizeof);
                break;

            default: error_wiimote("Data reporting mode is not supported (%x)", reporting_mode);
        }
    }

    void set_button(WiimoteButton button, bool pressed) {
        button_state &= ~cast(u16) button;
        button_state |= cast(u16) (pressed ? button : 0);
    }

    void set_accelerometer(u8 x, u8 y, u8 z) {
        accelerometer[0] = x;
        accelerometer[1] = y;
        accelerometer[2] = z;
    }

    void set_nunchuk_state(NunchukState state) {
        auto nunchuk = cast(NunchukExtension) extension;
        if (nunchuk is null) {
            return;
        }

        nunchuk.set_state(state);
    }
}
