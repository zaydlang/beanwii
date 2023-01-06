module emu.encryption.ticket;

import util.endian;
import util.number;

struct WiiTicketHeader {
    align(1):

    u32_be  signature_type;
    u8[256] signature;
    u8[60]  padding;
}

static assert(WiiTicketHeader.sizeof == 0x140);

struct WiiCcLimit {
    u32_be          limit_type;
    u32_be          maximum_usage;
}

static assert(WiiCcLimit.sizeof == 0x8);

struct WiiTicket {
    align(1):
    
    WiiTicketHeader header;

    u8[64]          signature_issuer;
    u8[60]          ecdh_data;
    u8              ticket_format_version;
    u16             reserved;
    u8[0x10]        encrypted_title_key;
    u8              unknown1;
    u64_be          ticket_id;
    u32_be          console_id;
    u64_be          title_id;
    u16_be          unknown2;
    u16_be          ticket_title_version;
    u32_be          permitted_titles_mask;
    u32_be          permit_mask;
    u8              title_export_allowed_using_prng_key;
    u8              common_key_index;
    u8[48]          unknown3;
    u8[64]          content_access_permissions;
    u8[2]           padding;
    WiiCcLimit[8]   cclimits;         
}

static assert(WiiTicket.sizeof == 0x2A4);