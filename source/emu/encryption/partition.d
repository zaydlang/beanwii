module emu.encryption.partition;

import emu.encryption.aes;
import emu.encryption.ticket;
import emu.hw.disk.layout;
import util.endian;
import util.log;
import util.number;

private static immutable u8[16] COMMON_KEY = [
    0xeb, 0xe4, 0x2a, 0x22, 
    0x5e, 0x85, 0x93, 0xe4, 
    0x48, 0xd9, 0xc5, 0x45, 
    0x73, 0x81, 0xaa, 0xf7
];

public void decrypt_partition(WiiTicket* ticket, WiiPartitionData* partition_data, u8* out_buf) {
    u8[16] title_key;
    get_title_key(ticket, title_key.ptr);
    u8[16] iv = (cast(u8*) partition_data)[0x3D0 .. 0x3E0];

    decrypt_aes(partition_data.payload, title_key, cast(u8[16]) iv, out_buf);
}

private void get_title_key(WiiTicket* ticket, u8* out_buf) {
    u8[16] initialization_vector;
    initialization_vector[0 .. 8] = (cast(u8*) &ticket.title_id)[0 .. 8];
    u8[16] encrypted_title_key = ticket.encrypted_title_key;

    decrypt_aes(encrypted_title_key, cast(u8[16]) COMMON_KEY, initialization_vector, out_buf);
}