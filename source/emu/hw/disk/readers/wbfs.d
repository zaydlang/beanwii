module emu.hw.disk.readers.wbfs;

import core.stdc.string;
import emu.encryption.partition;
import emu.encryption.ticket;
import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.layout;
import emu.hw.disk.readers.filereader;
import emu.hw.wii;
import std.algorithm;
import util.array;
import util.bitop;
import util.log;
import util.number;

// since there's basically, no information as to how the WBFS file format works, i consulted this
// for hints: https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DiscIO/WbfsBlob.cpp
// and this too: https://github.com/kwiirk/wbfs/blob/master/libwbfs/libwbfs.h
// maybe i should write some proper documentation as to how this works...
final class WbfsReader : FileReader {
    private enum WBFS_MAGIC_NUMBER        = 0x57424653; // "WBFS"
    private enum NUM_WII_SECTORS_PER_DISK = 143_432 * 2;
    private enum WII_SECTOR_SIZE          = 0x8000;
    private enum DISK_SIZE                = NUM_WII_SECTORS_PER_DISK * WII_SECTOR_SIZE;

    private u8*    disk_data;
    private size_t disk_size;

    private size_t num_sectors;
    private size_t hd_sector_size;
    private size_t wbfs_sector_size;
    private size_t num_disks;
    private size_t hd_sectors_per_wbfs_sector;
    private size_t num_wbfs_sectors_per_disk;

    // A WBFS address can be split into two parts. The chunk and the offset. This is because a wii disk
    // is split across multiple WBFS sectors. Each chunk corresponds to one WBFS sector. We can figure out
    // which sector a chunk corresponds to by reading the WLBA table. The offset is the offset into the 
    // sector.
    private size_t wbfs_disk_address_offset_mask;
    private size_t wbfs_disk_address_chunk_shift;

    private WiiPartitionHeader main_partition_header;
    private size_t main_partition_address;

    struct Sector {
        u8[] data;
    }

    Sector[u32] sectors;

    override public bool is_valid_file(u8[] file_data) {
        if (file_data.length < u32.sizeof) return false;

        u32 magic_number = file_data.read_be!u32(0);
        return magic_number == WBFS_MAGIC_NUMBER;
    }

    override public void load_file(Wii wii, u8[] file_data) {
        assert(is_valid_file(file_data));

        this.disk_data = file_data.ptr;
        this.disk_size = file_data.length;

        u32 magic_number = disk_data.read_be!u32(0);
        if (magic_number != WBFS_MAGIC_NUMBER) {
            error_wbfs("The given file does not contain the WBFS magic number! Are you sure this is a WBFS file?");
        }

        this.num_sectors                   = disk_data.read_be!u32(4);
        this.hd_sector_size                = 1 << disk_data.read_be!u8(8);
        this.wbfs_sector_size              = 1 << disk_data.read_be!u8(9);

        this.hd_sectors_per_wbfs_sector    = this.wbfs_sector_size / this.hd_sector_size;
        this.num_disks                     = this.hd_sector_size - 12;
        this.num_wbfs_sectors_per_disk     = DISK_SIZE / this.wbfs_sector_size;

        // Note that this.wbfs_sector_size is a power of two
        this.wbfs_disk_address_offset_mask = this.wbfs_sector_size - 1;
        this.wbfs_disk_address_chunk_shift = bfs(this.wbfs_sector_size);

        size_t target_wbfs_slot       = 0;
        bool   target_wbfs_slot_found = false;

        size_t disc_table_address = 12;
        for (int i = 0; i < this.num_disks; i++) {
            int slot = disk_data.read_le!u8(disc_table_address);

            if (slot != 0) {
                target_wbfs_slot = i;
                target_wbfs_slot_found = true;
                break;
            }
            
            disc_table_address++;
        }

        if (!target_wbfs_slot_found) {
            error_wbfs("Could not find a valid WBFS disk.");
        }

        log_wbfs("WBFS Dump:");
        log_wbfs("num_sectors:                   %d",   this.num_sectors);
        log_wbfs("hd_sector_size:                0x%x", this.hd_sector_size);
        log_wbfs("wbfs_sector_size:              0x%x", this.wbfs_sector_size);
        log_wbfs("hd_sectors_per_wbfs_sector:    %d",   this.hd_sectors_per_wbfs_sector);
        log_wbfs("num_disks:                     %d",   this.num_disks);
        log_wbfs("num_wbfs_sectors_per_disk:     %d",   this.num_wbfs_sectors_per_disk);
        log_wbfs("wbfs_disk_address_offset_mask: 0x%x", this.wbfs_disk_address_offset_mask);
        log_wbfs("wbfs_disk_address_chunk_shift: %d",   this.wbfs_disk_address_chunk_shift);
        WiiHeader* wii_header = new WiiHeader();
        this.disk_read(0, 0, wii_header, WiiHeader.sizeof);

        if (cast(u32) wii_header.wii_magic_word != WII_MAGIC_WORD) {
            error_disk("Wii magic word not found: %x != %x");
        }

        log_disk("Found game: %s", cast(char[64]) wii_header.game_title);

        WiiPartitionInfoTable* partition_info_table = new WiiPartitionInfoTable();
        this.disk_read(0, PARTITION_INFO_TABLE_OFFSET, partition_info_table, WiiPartitionInfoTableEntry.sizeof);

        bool wii_loaded = false;
        for (int entry = 0; entry < 4; entry++) {
            size_t total_partitions      =  cast(u32) partition_info_table.entries[entry].total_partitions;
            size_t partition_info_offset = (cast(u32) partition_info_table.entries[entry].partition_info_offset) << 2;
            log_wbfs("Total Partitions: %d", total_partitions);

            for (int partition_index = 0; partition_index < total_partitions; partition_index++) {
                WiiPartitionInfo partition_info;
                this.disk_read(0, partition_info_offset, &partition_info, WiiPartitionInfo.sizeof);

                WiiPartitionType partition_type = cast(WiiPartitionType) cast(u32) partition_info.partition_type;
                if (partition_type != WiiPartitionType.DATA) {
                    error_disk("This disk uses an unsupported partition type: %s", partition_type);
                }

                size_t partition_address = (cast(u32) partition_info.partition_offset) << 2;
                log_wbfs("Partition Address: %x", partition_address);

                WiiPartitionHeader partition_header;
                this.disk_read(0, partition_address, &partition_header, WiiPartitionHeader.sizeof);

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
                    this.disk_read(0, partition_data_address + encrypted_offset, &partition_data, WiiPartitionData.sizeof);
                    decrypt_partition(&partition_header.ticket, &partition_data, &decrypted_data[decrypted_offset]);

                    encrypted_offset += 0x8000;
                    decrypted_offset += 0x7C00;

                    log_wbfs("%x < %x", encrypted_offset, partition_data_size);
                }

                if (!wii_loaded) {
                    log_wbfs("Loading Wii disk with 0x%x bytes of decrypted data.", decrypted_data.length);

                    main_partition_header  = partition_header;
                    main_partition_address = partition_data_address;

                    wii.load_disk(this, decrypted_data, cast(u64) partition_header.ticket.title_id);
                    wii_loaded = true;
                    return;
                }
            }
        }

        if (!wii_loaded) {
            error_disk("No partitions found.");
        }

        log_wbfs("WBFS Disk loaded successfully.");
    }

    public void decrypted_disk_read(size_t disk_slot, size_t address, void* out_buffer, size_t size) {
        size_t first_sector_number                  = address / 0x7C00;
        size_t first_sector_offset_within_partition = first_sector_number * 0x8000;
        size_t offset_within_first_sector           = address % 0x7C00;
        size_t first_address                        = main_partition_address + first_sector_offset_within_partition;
    
        size_t current_address       = first_address;
        size_t current_sector_offset = offset_within_first_sector;

        u8[0x7C00] decrypted_sector;
        while (size > 0) {
            WiiPartitionData partition_data;
            log_wbfs("DECRYPT: Reading from address: %x", current_address);
            this.disk_read(disk_slot, current_address, &partition_data, WiiPartitionData.sizeof);
            decrypt_partition(&main_partition_header.ticket, &partition_data, decrypted_sector.ptr);

            size_t num_bytes_to_read = min(size, 0x7C00 - current_sector_offset);

            log_wbfs("DECRYPT memcpy: %x -> %x %x", decrypted_sector.ptr + current_sector_offset, out_buffer, num_bytes_to_read);
            memcpy(out_buffer, decrypted_sector.ptr + current_sector_offset, num_bytes_to_read);

            current_address       += 0x8000;
            size                  -= num_bytes_to_read;
            current_sector_offset  = 0;

            out_buffer = cast(void*) cast(size_t) out_buffer + num_bytes_to_read;
        }
    }

    private void disk_read(size_t disk_slot, size_t address, void* out_buffer, size_t size) {
        while (size > 0) {
            u16 wlba_entry = get_wlba_entry_for_address(disk_slot, address);

            size_t disk_chunk   = wlba_entry << this.wbfs_disk_address_chunk_shift;
            size_t disk_offset  = address & this.wbfs_disk_address_offset_mask;
            size_t disk_address = disk_chunk + disk_offset;

            size_t num_bytes_to_read = min(size, this.wbfs_sector_size - disk_offset);
            memcpy(out_buffer, this.disk_data + disk_address, num_bytes_to_read);
            out_buffer = cast(void*) cast(size_t) out_buffer + num_bytes_to_read;

            address += num_bytes_to_read;
            size    -= num_bytes_to_read;
        }
    }

    private u16 get_wlba_entry_for_address(size_t disk_slot, size_t address) {
        size_t wlba_entry_address = (disk_slot + 1) * this.hd_sector_size;                  // get to the beginning of the HD sector for this WBFS slot
        wlba_entry_address += 0x100;                                                        // get to the beginning of the wlba_table
        wlba_entry_address += (address >> this.wbfs_disk_address_chunk_shift) * u16.sizeof; // get to the entry that corresponds to the address
        
        return disk_data.read_be!u16(wlba_entry_address);
    }
}
