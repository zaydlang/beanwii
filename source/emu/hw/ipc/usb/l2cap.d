module emu.hw.ipc.usb.l2cap;

// more like l2crap am i right

import util.endian;
import util.number;

enum {
    L2CAP_CONNECT_RSP = 0x3,
    L2CAP_CONFIG_REQ  = 0x4,
    L2CAP_CONFIG_RSP  = 0x5,
}

struct WiimoteL2capCommand {
    align(1):

    L2capCommandHeader header;
    ReportDirection report_direction;

    union {
        InputReport input_report;
        OutputReport output_report;
    }
}

struct L2capCommandHeader {
    align(1):

    u16 length;
    Channel channel;
}

enum Channel : u16 {
    // maybe inaccurate names but whatever
    BluetoothHCI = 0x0001,
    WiimoteHID   = 0x0041,
}

enum ReportDirection : u8 {
    Input  = 0xa1,
    Output = 0xa2,
}

struct InputReport {
    align(1):

    InputReportId report_id;

    union {
        align(1):

        StatusInformationReport    status_information_report;
        AcknowledgeOutputReport    acknowledge_output_report;
        ReadMemoryAndRegistersData read_memory_and_registers_data;
        DataReport30               data_report_30;
    }
}

struct OutputReport {
    align(1):

    OutputReportId report_id;

    union {
        align(1):

        PlayerLEDs                     player_leds;
        DataReportingMode              data_reporting_mode;
        IRCameraEnable                 ir_camera_enable;
        SpeakerEnableReport            speaker_enable;
        SpeakerMuteReport              speaker_mute;
        StatusInformationRequestReport status_information_request;
        ReadMemoryAndRegistersReport   read_memory_and_registers;
        WriteMemoryAndRegistersReport  write_memory_and_registers;
        IRCameraEnable2                ir_camera_enable2;
    }
}

enum InputReportId : u8 {
    StatusInformation          = 0x20,
    ReadMemoryAndRegistersData = 0x21,
    AcknowledgeOutputReport    = 0x22,

    DataReport30               = 0x30,
    DataReport31               = 0x31,
    DataReport32               = 0x32,
    DataReport33               = 0x33,
    DataReport34               = 0x34,
    DataReport35               = 0x35,
    DataReport36               = 0x36,
    DataReport37               = 0x37,
    DataReport38               = 0x38,
    DataReport39               = 0x39,
    DataReport3a               = 0x3a,
    DataReport3b               = 0x3b,
    DataReport3c               = 0x3c,
    DataReport3d               = 0x3d,
    DataReport3e               = 0x3e,
    DataReport3f               = 0x3f,
}

enum OutputReportId : u8 {
    Rumble                   = 0x10,
    PlayerLEDs               = 0x11,
    DataReportingMode        = 0x12,
    IRCameraEnable           = 0x13,
    SpeakerEnable            = 0x14,
    StatusInformationRequest = 0x15,
    WriteMemoryAndRegisters  = 0x16,
    ReadMemoryAndRegisters   = 0x17,
    SpeakerData              = 0x18,
    SpeakerMute              = 0x19,
    IRCameraEnable2          = 0x1a
}

struct PlayerLEDs {
    align(1):

    u8 led_status;
}

static assert(PlayerLEDs.sizeof == 1);

struct ReadMemoryAndRegistersReport {
    align(1):

    AddressSpace address_space;
    u8[3] address;
    u16_be size;
}

static assert(ReadMemoryAndRegistersReport.sizeof == 6);

struct WriteMemoryAndRegistersReport {
    align(1):

    AddressSpace address_space;
    u8[3] address;
    u8 size;
    u8[16] data;
}

static assert(WriteMemoryAndRegistersReport.sizeof == 21);

enum AddressSpace : u8 {
    Memory = 0x00,

    // Both are used for the same registers
    Registers1 = 0x04,
    Registers2 = 0x08,
}

struct DataReportingMode {
    align(1):

    ContinuousMode continuous_mode;
    u8 report_mode;
}

static assert(DataReportingMode.sizeof == 2);

enum ContinuousMode : u8 {
    Normal     = 0x00,
    Continuous = 0x04,
}

struct SpeakerEnableReport {
    align(1):

    SpeakerEnablement speaker_enablement;
}

static assert(SpeakerEnableReport.sizeof == 1);

enum SpeakerEnablement : u8 {
    Enabled  = 0x04,
    Disabled = 0x00,
}

struct SpeakerMuteReport {
    align(1):

    SpeakerMute speaker_mute;
}

static assert(SpeakerMuteReport.sizeof == 1);

enum SpeakerMute : u8 {
    Mute   = 0x04,
    Unmute = 0x00,
}

struct StatusInformationRequestReport {
    align(1):

    u8 something;
}

static assert(StatusInformationRequestReport.sizeof == 1);

struct ReadMemoryAndRegistersData {
    align(1):

    u8[2] button_state;
    u8 size_and_error; // top 4 bits size, bottom 4 bits error
    u16_be data_offset;
    u8[16] data;
}

static assert(ReadMemoryAndRegistersData.sizeof == 21);

struct IRCameraEnable {
    align(1):
    
    IRCameraState ir_camera_state;
}

static assert(IRCameraEnable.sizeof == 1);

enum IRCameraState : u8 {
    On  = 0x04,
    Off = 0x00,
}

alias IRCameraEnable2 = IRCameraEnable;

struct StatusInformationReport {
    align(1):

    u8[2] button_state;
    u8 led_and_flags;
    u8[2] padding;
    u8 battery_level;
}

struct AcknowledgeOutputReport {
    align(1):

    u8[2] button_state;
    OutputReportId report_id; // top 4 bits size, bottom 4 bits error
    u8 error_code;
}

static assert(AcknowledgeOutputReport.sizeof == 4);

struct DataReport30 {
    align(1):

    u8[2] button_state;
}

static assert(DataReport30.sizeof == 2);
