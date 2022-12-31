module emu.hw.disk.readers.diskreader;

import util.number;

interface DiskReader {
    public void load_disk(u8* disk_data, size_t disk_size);
    public void disk_read(size_t disk_slot, size_t address, void* out_buffer, size_t size);
}
