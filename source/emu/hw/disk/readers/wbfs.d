module emu.hw.disk.readers.wbfs;

import core.stdc.string;
import emu.hw.disk.readers.diskreader;
import util.array;
import util.bitop;
import util.log;
import util.number;

// since there's basically, no information as to how the WBFS file format works, i consulted this
// for hints: https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DiscIO/WbfsBlob.cpp
// and this too: https://github.com/kwiirk/wbfs/blob/master/libwbfs/libwbfs.h
// maybe i should write some proper documentation as to how this works...

final class WbfsReader : DiskReader {
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

    private u16[] wlba_table;

    override public void load_disk(u8* disk_data, size_t disk_size) {
        this.disk_data = disk_data;
        this.disk_size = disk_size;

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
        log_wbfs("num_sectors:                %d",   this.num_sectors);
        log_wbfs("hd_sector_size:             0x%x", this.hd_sector_size);
        log_wbfs("wbfs_sector_size:           0x%x", this.wbfs_sector_size);
        log_wbfs("hd_sectors_per_wbfs_sector: %d",   this.hd_sectors_per_wbfs_sector);
        log_wbfs("num_disks:                  %d",   this.num_disks);
        log_wbfs("num_wbfs_sectors_per_disk:  %d",   this.num_wbfs_sectors_per_disk);
    }

    override public void disk_read(size_t disk_slot, size_t address, void* out_buffer, size_t size) {
        u16 wlba_entry = get_wlba_entry_for_address(disk_slot, address);

        size_t disk_chunk   = wlba_entry << this.wbfs_disk_address_chunk_shift;
        size_t disk_offset  = address & this.wbfs_disk_address_offset_mask;
        size_t disk_address = disk_chunk + disk_offset;
        log_wbfs("disk_slot: %d, address: 0x%x, wlba_entry: 0x%x, disk_chunk: 0x%x, disk_offset: 0x%x, disk_address: 0x%x", disk_slot, address, wlba_entry, disk_chunk, disk_offset, disk_address);

        memcpy(out_buffer, this.disk_data + disk_address, size);
    }

    private u16 get_wlba_entry_for_address(size_t disk_slot, size_t address) {
        size_t wlba_entry_address = (disk_slot + 1) * this.hd_sector_size;                  // get to the beginning of the HD sector for this WBFS slot
        wlba_entry_address += 0x100;                                                        // get to the beginning of the wlba_table
        wlba_entry_address += (address >> this.wbfs_disk_address_chunk_shift) * u16.sizeof; // get to the entry that corresponds to the address
        
        log_wbfs("wlba_entry_address: 0x%x", wlba_entry_address);
        return disk_data.read_be!u16(wlba_entry_address);
    }
}
