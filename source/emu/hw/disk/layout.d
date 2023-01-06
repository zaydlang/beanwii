module emu.hw.disk.layout;

import emu.encryption.ticket;
import util.endian;
import util.number;

enum WII_MAGIC_WORD              = 0x5D1C9EA3;
enum GAMECUBE_MAGIC_WORD         = 0xC2339F3D;
enum PARTITION_INFO_TABLE_OFFSET = 0x40000;

struct WiiHeader {
    align(1):

    u8     disk_id;
    u16_be game_code;
    u8     region_code;
    u16_be maker_code;
    u8     disk_number;
    u8     disk_version;
    u8     audio_streaming_enabled;
    u8     stream_buffer_size;
    u8[14] unused;
    u32_be wii_magic_word;
    u32_be gamecube_magic_word;
    u8[64] game_title;
    u8     disable_hash_verification;
    u8     disable_disc_encryption;
}

static assert (WiiHeader.sizeof == 0x62);

struct WiiPartitionInfoTableEntry {
    align(1):

    u32_be total_partitions;
    u32_be partition_info_offset;
}

static assert (WiiPartitionInfoTableEntry.sizeof == 0x8);

struct WiiPartitionInfoTable {
    align(1):
    WiiPartitionInfoTableEntry[4] entries;
}

static assert (WiiPartitionInfoTable.sizeof == 0x20);

struct WiiPartitionInfo {
    align(1):
    u32_be partition_offset;
    u32_be partition_type;
}

static assert (WiiPartitionInfo.sizeof == 0x8);

enum WiiPartitionType {
    DATA    = 0,
    UPDATE  = 1,
    CHANNEL = 2
}

enum WiiPartitionDataPayloadLength = 0x400 * 31;

struct WiiPartitionHeader {
    WiiTicket ticket;

    u32_be    tmd_size;
    u32_be    tmd_offset;
    u32_be    cert_chain_size;
    u32_be    cert_chain_offset;
    u32_be    h3_offset;
    u32_be    data_offset;
    u32_be    data_size;
}

static assert (WiiPartitionHeader.sizeof == 0x2c0);

struct WiiPartitionData {
    align(1):
    
    u8[31][20] h0_sha1_hash;
    u8[20]     padding1;
    u8[8][20]  h1_sha1_hash;
    u8[32]     padding2;
    u8[8][20]  h2_sha1_hash;
    u8[32]     padding3;

    u8[WiiPartitionDataPayloadLength] payload;
}

static assert (WiiPartitionData.sizeof == 0x8000);

enum WII_DOL_OFFSET       = 0x420; // blaze it
enum WII_APPLOADER_OFFSET = 0x02440;
