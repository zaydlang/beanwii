module emu.hw.wii;

import emu.encryption.partition;
import emu.encryption.ticket;
import emu.hw.broadway.cpu;
import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.layout;
import emu.hw.disk.readers.diskreader;
import emu.hw.disk.readers.wbfs;
import emu.hw.memory.strategy.memstrategy;
import util.array;
import util.log;
import util.number;

final class Wii {
    private BroadwayCpu broadway_cpu;
    private Mem         mem;

    this() {
        this.mem          = new Mem();
        this.broadway_cpu = new BroadwayCpu(mem);
    }

    public void run() {
        // The following initial GPR states were taken from dolphin.
        broadway_cpu.set_gpr(1, 0x816ffff0); // ????
        broadway_cpu.set_gpr(2, 0x81465cc0);
        broadway_cpu.set_gpr(13, 0x81465320);

        while (true) {
            this.broadway_cpu.run_instruction();
        }
    }

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

                this.run_apploader(decrypted_data);

                size_t dol_address = decrypted_data.read_be!u32(WII_DOL_OFFSET) << 2;
                log_wbfs("Dol address: 0x%x", dol_address);
                log_wbfs("Dol debug: 0x%x", decrypted_data.read_be!u32(dol_address + 0x2224));

                for (int i = 0; i <= 0x2224; i += 4) {
                    log_wbfs("[%x] = 0x%x", i, decrypted_data.read_be!u32(dol_address + i));
                }

                WiiDol* dol = cast(WiiDol*) &decrypted_data[dol_address];
                dol.data = decrypted_data[dol_address .. partition_data_size];

                this.mem.map_dol(dol);
                this.broadway_cpu.set_pc(cast(u32) dol.header.entry_point);
            }
        }
    }

    private void run_apploader(u8[] disk_data) {
        WiiApploaderHeader* apploader = cast(WiiApploaderHeader*) &disk_data[WII_APPLOADER_OFFSET];
        this.mem.map_buffer(&disk_data[WII_APPLOADER_OFFSET + WiiApploaderHeader.sizeof], cast(s32) apploader.size, WII_APPLOADER_LOAD_ADDRESS);

        log_disk("Apploader info:");
        log_disk("  Size:         %x", cast(s32) apploader.size);
        log_disk("  Trailer size: %x", cast(s32) apploader.trailer_size);
        log_disk("  Entry point:  %x", cast(u32) apploader.entry_point);

        // r1 is reserved for the stack, so let's just set the stack somewhere arbitrary that won't
        // conflict with the apploader code
        this.broadway_cpu.set_gpr(1, 0x8001_0000);

        // arguments
        this.broadway_cpu.set_gpr(3, 0x8000_0000);
        this.broadway_cpu.set_gpr(4, 0x8000_0004);
        this.broadway_cpu.set_gpr(5, 0x8000_0008);

        this.broadway_cpu.set_pc(cast(u32) apploader.entry_point);
        this.broadway_cpu.run_until_return();
        while (true) {}
    }
}
