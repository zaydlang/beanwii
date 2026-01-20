module emu.hw.ipc.usb.bluetooth_types;

import util.endian;
import util.number;

enum HciEventCode : u8 {
    CommandComplete = 0x0E,
    CommandStatus = 0x0F,
    ConnectionComplete = 0x03,
    ConnectionRequest = 0x04,
    AuthenticationComplete = 0x06,
    RemoteNameRequestComplete = 0x07,
    LinkKeyRequestReply = 0x0B,
    LinkKeyNotification = 0x18,
    NumberOfCompletedPackets = 0x13,
    ModeChange = 0x14,
    ConnectionPacketTypeChanged = 0x1D,
    ReadClockOffsetComplete = 0x1C,
    ReadRemoteVersionInformationComplete = 0x0C,
    ReadRemoteSupportedFeaturesComplete = 0x0B,
    RoleChange = 0x12,
    ReadStoredLinkKeyComplete = 0x15,
}

enum HciCommandOpcode : u16 {
    Reset = 0x0C03,
    ReadLocalVersionInformation = 0x1001,
    ReadLocalSupportedFeatures = 0x1003,
    ReadBufferSize = 0x1005,
    ReadBdAddr = 0x1009,
    WriteLocalName = 0x0C13,
    ReadStoredLinkKey = 0x0C0D,
    DeleteStoredLinkKey = 0x0C12,
    WritePinType = 0x0C0A,
    WritePageTimeout = 0x0C18,
    WriteScanEnable = 0x0C1A,
    WriteClassOfDevice = 0x0C24,
    HostBufferSize = 0x0C33,
    WriteLinkSupervisionTimeout = 0x0C37,
    WriteInquiryScanType = 0x0C43,
    WriteInquiryMode = 0x0C45,
    WritePageScanType = 0x0C47,
    AcceptConnectionRequest = 0x0409,
    ChangeConnectionPacketType = 0x040F,
    AuthenticationRequested = 0x0411,
    RemoteNameRequest = 0x0419,
    ReadRemoteSupportedFeatures = 0x041B,
    ReadRemoteVersionInformation = 0x041D,
    ReadClockOffset = 0x041F,
    SniffMode = 0x0803,
    WriteLinkPolicySettings = 0x080D,
    VendorSpecific4C = 0xFC4C,
    VendorSpecific4F = 0xFC4F,
}

struct HciEvt {
    u8 evt_code;
    u8 len;
}

struct HciEventHeader {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
}

static assert(HciEventHeader.sizeof == 2);

struct HciCommandCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_hci_command_packets;
    u16_le command_opcode;
    u8 status;
}

static assert(HciCommandCompleteEvent.sizeof == 6);

struct HciCommandStatusEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u8 num_hci_command_packets;
    u16_le command_opcode;
}

static assert(HciCommandStatusEvent.sizeof == 6);

struct HciConnectionCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
    u8[6] bd_addr;
    u8 link_type;
    u8 encryption_enabled;
}

static assert(HciConnectionCompleteEvent.sizeof == 13);

struct HciConnectionRequestEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8[6] bd_addr;
    u8[3] class_of_device;
    u8 link_type;
}

static assert(HciConnectionRequestEvent.sizeof == 12);

struct HciRoleChangeEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u8[6] bd_addr;
    u8 new_role;
}

static assert(HciRoleChangeEvent.sizeof == 10);

struct HciReadBufferSizeResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_hci_command_packets;
    u16_le command_opcode;
    u8 status;
    u16_le hc_acl_data_packet_length;
    u8 hc_synchronous_data_packet_length;
    u16_le hc_total_num_acl_data_packets;
    u16_le hc_total_num_synchronous_data_packets;
}

static assert(HciReadBufferSizeResponse.sizeof == 13);

struct HciReadLocalVersionResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_hci_command_packets;
    HciCommandOpcode command_opcode;
    u8 status;
    u8 hci_version;
    u16 hci_revision;
    u8 lmp_pal_version;
    u16 manufacturer_name;
    u16 lmp_pal_subversion;
}

static assert(HciReadLocalVersionResponse.sizeof == 14);

struct HciReadLocalFeaturesResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_hci_command_packets;
    HciCommandOpcode command_opcode;
    u8 status;
    u8[8] lmp_features;
}

static assert(HciReadLocalFeaturesResponse.sizeof == 14);

struct HciReadBdAddrResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_hci_command_packets;
    HciCommandOpcode command_opcode;
    u8 status;
    u8[6] bd_addr;
}

static assert(HciReadBdAddrResponse.sizeof == 12);

struct HciAuthenticationCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
}

static assert(HciAuthenticationCompleteEvent.sizeof == 5);

struct HciRemoteNameRequestCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u8[6] bd_addr;
    char[248] remote_name;
}

static assert(HciRemoteNameRequestCompleteEvent.sizeof == 257);

struct HciReadClockOffsetCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
    u16_le clock_offset;
}

static assert(HciReadClockOffsetCompleteEvent.sizeof == 7);

struct HciReadRemoteVersionCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
    u8 lmp_pal_version;
    u16_le manufacturer_name;
    u16_le lmp_pal_subversion;
}

static assert(HciReadRemoteVersionCompleteEvent.sizeof == 10);

struct HciReadRemoteFeaturesCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
    u8[8] lmp_features;
}

static assert(HciReadRemoteFeaturesCompleteEvent.sizeof == 13);

struct HciConnectionPacketTypeChangedEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
    u16_le packet_type;
}

static assert(HciConnectionPacketTypeChangedEvent.sizeof == 7);

struct HciNumberOfCompletedPacketsEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 number_of_handles;
    u16 connection_handle;
    u16_le num_completed_packets;
}

static assert(HciNumberOfCompletedPacketsEvent.sizeof == 7);

struct HciReadStoredLinkKeyCompleteEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16_le max_num_keys;
    u16_le num_keys_read;
}

static assert(HciReadStoredLinkKeyCompleteEvent.sizeof == 7);

struct LinkKeyData {
    align(1):
    u8[6] bd_addr;
    u8[16] link_key;
}

static assert(LinkKeyData.sizeof == 22);

struct HciLinkKeyEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    LinkKeyData[5] link_keys;
}

static assert(HciLinkKeyEvent.sizeof == 112);

struct HciReadStoredLinkKeysResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_keys;
    LinkKeyData[5] link_keys;
}

static assert(HciReadStoredLinkKeysResponse.sizeof == 113);

struct ReadStoredLinkKeyCommandCompleteResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_hci_command_packets;
    u16_le command_opcode;
    u8 status;
    u16_le max_num_keys;
    u16_le num_keys_read;
}

static assert(ReadStoredLinkKeyCommandCompleteResponse.sizeof == 10);

struct HciModeChangeEvent {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 status;
    u16 connection_handle;
    u8 current_mode;
    u16_be interval;
}

static assert(HciModeChangeEvent.sizeof == 8);

struct HciAclPacketCountResponse {
    align(1):
    HciEventCode event_code;
    u8 parameter_length;
    u8 num_handles;
    
    struct HandleData {
        u16 connection_handle;
        u16 num_acl_packets;
    }
    
    HandleData[5] handle_data; // Wii seems to send 5
}

static assert(HciAclPacketCountResponse.sizeof == 23);

struct HciAclHeader {
    align(1):
    u16 handle_and_flags;
    u16 length;
}

static assert(HciAclHeader.sizeof == 4);
