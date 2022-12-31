module emu.hw.disk.diskloader;

import emu.encryption.partition;
import emu.encryption.ticket;
import emu.hw.disk.dol;
import emu.hw.disk.layout;
import emu.hw.disk.readers.diskreader;
import emu.hw.disk.readers.wbfs;
import util.array;
import util.log;
import util.number;

public void load_wii_disk(u8* disk_data, size_t length) {
    DiskReader disk_reader = new WbfsReader();
    disk_reader.load_disk(disk_data, length);

    WiiHeader* wii_header = new WiiHeader();
    disk_reader.disk_read(0, 0, wii_header, WiiHeader.sizeof);

    if (cast(u32) wii_header.wii_magic_word != WII_MAGIC_WORD) {
        error_disk("Wii magic word not found: %x != %x");
    }

    log_disk("Found game: %s", cast(char[64]) wii_header.game_title);

    WiiPartitionInfoTable* partition_info_table = new WiiPartitionInfoTable();
    disk_reader.disk_read(0, PARTITION_INFO_TABLE_OFFSET, partition_info_table, WiiPartitionInfoTableEntry.sizeof);

    for (int entry = 0; entry < 4; entry++) {
        size_t total_partitions      =  cast(u32) partition_info_table.entries[entry].total_partitions;
        size_t partition_info_offset = (cast(u32) partition_info_table.entries[entry].partition_info_offset) << 2;

        for (int partition_index = 0; partition_index < total_partitions; partition_index++) {
            WiiPartitionInfo partition_info;
            disk_reader.disk_read(0, partition_info_offset, &partition_info, WiiPartitionInfo.sizeof);

            WiiPartitionType partition_type = cast(WiiPartitionType) cast(u32) partition_info.partition_type;
            if (partition_type != WiiPartitionType.DATA) {
                error_disk("This disk uses an unsupported partition type: %s", partition_type);
            }

            size_t partition_address = (cast(u32) partition_info.partition_offset) << 2;
            log_wbfs("Partition Address: %x", partition_address);

            WiiPartitionHeader partition_header;
            disk_reader.disk_read(0, partition_address, &partition_header, WiiPartitionHeader.sizeof);

            size_t partition_data_address = partition_address + ((cast(u32) partition_header.data_offset) << 2);
            size_t partition_data_size    = (cast(u32) partition_header.data_size) << 2;

            log_wbfs("Partition Data Address: %x", partition_data_address);
            log_wbfs("Partition Data Size:    %x", partition_data_size);
            log_wbfs("Ticket: %x", cast(u32) partition_header.ticket.header.signature_type);

            u8[] decrypted_data = new u8[partition_data_size];

            size_t encrypted_offset = 0;
            size_t decrypted_offset = 0;

            while (encrypted_offset < partition_data_size) {
                WiiPartitionData partition_data;
                disk_reader.disk_read(0, partition_data_address + encrypted_offset, &partition_data, WiiPartitionData.sizeof);
                decrypt_partition(&partition_header.ticket, &partition_data, &decrypted_data[decrypted_offset]);

                encrypted_offset += 0x8000;
                decrypted_offset += 0x7C00;
            }

            size_t dol_address = decrypted_data.read_be!u32(WII_DOL_OFFSET) << 2;
            log_wbfs("Dol address: 0x%x", dol_address);

            WiiDol* dol = cast(WiiDol*) &decrypted_data[dol_address];
            // log everything about dol
    // u32_be[7]  text_offset;
    // u32_be[11] data_offset;
    // u32_be[7]  text_address;
    // u32_be[11] data_address;
    // u32_be[7]  text_size;
    // u32_be[11] data_size;
    // u32_be     bss_address;
    // u32_be     bss_size;
    // u32_be     entry_point;
    // u8[28]     padding;
    // log all this

            log_wbfs("Dol Text[0]: %x %x", cast(u32) dol.text_address[0], cast(u32) dol.text_size[0]);
            log_wbfs("Dol Text[1]: %x %x", cast(u32) dol.text_address[1], cast(u32) dol.text_size[1]);
            log_wbfs("Dol Text[2]: %x %x", cast(u32) dol.text_address[2], cast(u32) dol.text_size[2]);
            log_wbfs("Dol Text[3]: %x %x", cast(u32) dol.text_address[3], cast(u32) dol.text_size[3]);
            log_wbfs("Dol Text[4]: %x %x", cast(u32) dol.text_address[4], cast(u32) dol.text_size[4]);
            log_wbfs("Dol Text[5]: %x %x", cast(u32) dol.text_address[5], cast(u32) dol.text_size[5]);
            log_wbfs("Dol Text[6]: %x %x", cast(u32) dol.text_address[6], cast(u32) dol.text_size[6]);
            
        }
    }
}
