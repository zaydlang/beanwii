module emu.hw.ipc.filemanager;

import emu.hw.disk.readers.filereader;
import emu.hw.ipc.error;
import emu.hw.ipc.ipc;
import emu.hw.ipc.usb.usb;
import emu.hw.memory.strategy.memstrategy;
import std.conv;
import std.file;
import std.format;
import util.bitop;
import util.log;
import util.number;

extern(C) {
    extern int errno;
    int mkdir(const char *path, int mode);
}

alias FileDescriptor = int;

enum OpenMode {
    NoAccess  = 0,
    Read      = 1,
    Write     = 2,
    ReadWrite = 3
}

final class FileManager {
    class File {
        string path;

        this(string path) {
            this.path = path;
        }

        int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            error_ipc("ioctl not implemented for %s", path);
            return 0;
        }

        void ioctlv(u32 request_paddr, int ioctl, int argcin, int argcio, u32 data_paddr) {
            error_ipc("ioctlv not implemented for %s", path);
        }

        int read(u8[] buffer, int size) {
            error_ipc("read not implemented for %s", path);
            return 0;
        }

        int write(u8* buffer, int size) {
            error_ipc("write not implemented for %s", path);
            return 0;
        }

        int seek(int offset, int whence) {
            error_ipc("seek not implemented for %s", path);
            return 0;
        }

        void close() {}
    }

    final class DiskDi : File {
        FileReader file_reader;
        this(FileReader file_reader) {
            super("/dev/di");

            this.file_reader = file_reader;
        }

        bool cover_irq_pending = false;

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            if (ioctl == 0x86) {
                cover_irq_pending = false;
            } else if (ioctl == 0x12) {
                u8[] data = [
                    0x00, 0x00, 0x00, 0x00,
                    0x20, 0x02, 0x04, 0x02,
                    0x61, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00,
                ];

                for (int i = 0; i < 16; i++) {
                    mem.paddr_write_u8(output_buffer + i, data[i]);
                }

                return 1;
            } else if (ioctl == 0x71) {
                u32 size   = mem.paddr_read_u32(input_buffer + 4);
                u32 offset = mem.paddr_read_u32(input_buffer + 8) << 2;
                log_disk("Read %x bytes from disk at offset %x to %x (%x)", size, offset, output_buffer, output_buffer_length);

                if (output_buffer_length < size) {
                    error_ipc("Output buffer too small for read");
                }

                u8[] buffer = new u8[size];
                file_reader.decrypted_disk_read(0, offset, buffer.ptr, size);
                
                for (int i = 0; i < size; i++) {
                    if (buffer[i] != 0) {
                        log_disk("non-zero byte at %x: %x", i, buffer[i]);
                    }
                }
                mem.write_bulk(output_buffer, buffer.ptr, size);
                return 1;
            }

            return 0;
        }
    }

    final class NANDBootInfo : File {

        struct NANDBootInfoInner {
        align(1):
            u32 checksum;
            u32 argsoff;
            u8[2] unknown1;
            u8 apptype;
            u8 titletype;
            u32 launchcode;
            u32[2] unknown2;
            u64 launcher;
            u8[0x1000] argbuf;
        }

        u8[NANDBootInfoInner.sizeof] data;
        this() {
            super("/shared2/sys/NANDBOOTINFO");

            // wtf is this
            NANDBootInfoInner nand_boot_info;
            nand_boot_info.argsoff    = 0x1000;
            nand_boot_info.apptype    = 0x80;
            nand_boot_info.titletype  = 0;
            nand_boot_info.launchcode = 0;
            nand_boot_info.launcher   = 0;

            for (size_t i = 0; i < nand_boot_info.argbuf.length; i++) {
                nand_boot_info.argbuf[i] = 0;
            }

            u32 checksum = 0;
            u32* buffer = cast(u32*) &nand_boot_info;
            for (size_t i = 1; i < NANDBootInfoInner.sizeof / 4; i++) {
                checksum += buffer[i];
            }

            nand_boot_info.checksum = checksum;

            for (size_t i = 0; i < NANDBootInfoInner.sizeof; i++) {
                data[i] = (cast(u8*) &nand_boot_info)[i];
            }
        }

        int offset = 0;
        override int read(u8[] buffer, int size) {
            if (offset + size > NANDBootInfoInner.sizeof) {
                error_ipc("Read past end of file %s", path);
            }

            buffer[0 .. size] = data[offset .. offset + size];
            offset += size;

            return size;
        }
    }

    final class DevNetKdTime : File {
        this() {
            super("/dev/net/kd/time");
        }

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            if (ioctl == 0x17) {
                return 0;
            } else {
                error_ipc("Unknown ioctl %d", ioctl);
            }

            return 0;
        }
    }

    final class DevES : File {
        this() {
            super("/dev/es");
        }

        override void ioctlv(u32 request_paddr, int ioctl, int argcin, int argcio, u32 data_paddr) {
            log_ipc("DevES::ioctlv(%d, %d, %d, %d)", ioctl, argcin, argcio, data_paddr);

            if (ioctl == 0x20) {
                // GetTitleID
                u32 addr = mem.paddr_read_u32(data_paddr);
                mem.paddr_write_u64(addr, title_id);
                mem.paddr_write_u32(data_paddr + 4, 8);
                log_ipc("DevES::GetTitleID(%x)", title_id);
            } else if (ioctl == 0x1d) {
                u32 addr = mem.paddr_read_u32(data_paddr);
                auto requested_title_id = mem.paddr_read_u64(addr);
                string title_dir = "/title/%08x/%08x/data".format(cast(u32) (title_id >> 32), cast(u32) title_id);
                addr = mem.paddr_read_u32(data_paddr + 8);
                log_ipc("DevES::GetTitleDirectory(%x) -> %s", requested_title_id, title_dir);

                for (int i = 0; i < title_dir.length; i++) {
                    mem.paddr_write_u8(addr + i, cast(u8) title_dir[i]);
                }
                mem.paddr_write_u8(addr + cast(int) title_dir.length, 0);
                mem.paddr_write_u32(data_paddr + 0xC, cast(u32) title_dir.length);
            } else {
                error_ipc("Unknown ioctlv %d", ioctl);
            }

            ipc_response_queue.push_later(request_paddr, 0, 40_000);
        }

        u64 title_id = 0;
        void set_title_id(u64 title_id) {
            this.title_id = title_id;
        }
    }

    final class DataFile : File {
        ubyte[] data;

        this(string path, ubyte[] data) {
            super(path);
            this.data = data;
        }

        int offset = 0;

        override int read(u8[] buffer, int size) {
            if (offset + size > data.length) {
                error_ipc("Read past end of file %s", path);
            }

            buffer[0 .. size] = data[offset .. offset + size];
            offset += size;

            return size;
        }

        override int write(u8* buffer, int size) {
            if (offset + size > data.length) {
                error_ipc("Write past end of file %s", path);
            }

            data[offset .. offset + size] = buffer[0 .. size];
            offset += size;

            log_ipc("DataFile::write(%s, %d, %s)", path, size, buffer[0 .. size]);

            return size;
        }
    }

    final class EventHook : File {
        this() {
            super("/dev/stm/eventhook");
        }

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            // this only matters for resetting the wii
            return 0;
        }
    }

    final class EncryptedBuffer : File {
        u8[] data;

        this(string path, u8[] stuff) {
            super(path);

            u32 key = 0x73B5DBFA;
            
            for (int i = 0; i < stuff.length; i++) {
                data ~= stuff[i] ^ (key & 0xff);
                key = (key << 1) | (key >> 31);
            }
        }

        int offset = 0;
        override int read(u8[] buffer, int size) {
            if (offset + size > data.length) {
                error_ipc("Read past end of file %s", path);
            }

            buffer[0 .. size] = data[offset .. offset + size];
            offset += size;

            return size;
        }
    }

    final class TitleState : File {
        struct StateFlags {
        align(1):
            u32 checksum;
            u8 flags;
            u8 type;
            u8 discstate;
            u8 returnto;
            u32[6] unknown;
        }

        u8[StateFlags.sizeof] data;

        this() {
            super("/title/00000001/00000002/data/state.dat");

            // ????????
            StateFlags state_flags;
            state_flags.flags     = 0; // return to menu
            state_flags.type      = 3; // no clue
            state_flags.discstate = 1; // wiiiiii
            state_flags.returnto  = 0; // return to menu

            u32 checksum = 0;
            u32* buffer = cast(u32*) &state_flags;
            for (size_t i = 1; i < StateFlags.sizeof / 4; i++) {
                checksum += buffer[i];
            }

            state_flags.checksum = checksum;

            for (size_t i = 0; i < StateFlags.sizeof; i++) {
                data[i] = (cast(u8*) &state_flags)[i];
            }
        }

        int offset = 0;
        override int read(u8[] buffer, int size) {
            if (offset + size > StateFlags.sizeof) {
                error_ipc("Read past end of file %s", path);
            }

            buffer[0 .. size] = data[offset .. offset + size];
            offset += size;

            return size;
        }
    }

    final class DevFS : File {
        this() {
            super("/dev/fs");
            
            // go and fuck yourself
            try { "/home/zaydq/wii/tmp".rmdirRecurse(); } catch (Exception e) {}
            assert_ipc(mkdir("/home/zaydq/wii/tmp", std.conv.octal!"777") == 0, "failed to create /tmp: %d", errno);
        }

        void set_title_id(u64 title_id) {
            string title_dir = "/home/zaydq/wii/title/%08x/%08x/data".format(cast(u32) (title_id >> 32), cast(u32) title_id);
            try { title_dir.mkdirRecurse(); } catch (Exception e) {}
        }

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            if (ioctl == 0x3) {
                // CreateDir
                // u32 addr = mem.paddr_read_u32(input_buffer);
                auto owner_id = mem.paddr_read_u32(input_buffer + 0);
                auto group_id = mem.paddr_read_u16(input_buffer + 4);
                
                string filename = "";
                for (int i = 0; i < 0x40; i++) {
                    auto c = mem.paddr_read_u8(input_buffer + 6 + i);
                    if (c == 0) {
                        break;
                    }
                
                    filename ~= cast(char) c;
                }

                log_ipc("DevFS::CreateDir(%s, %d, %d)", filename, owner_id, group_id);
                // std.file.mkdir("/home/zaydq/wii" ~ filename);
            } else if (ioctl == 0x9) {
                // CreateFile
                auto owner_id = mem.paddr_read_u32(input_buffer + 0);
                auto group_id = mem.paddr_read_u16(input_buffer + 4);

                string filename = "";
                for (int i = 0; i < 0x40; i++) {
                    auto c = mem.paddr_read_u8(input_buffer + 6 + i);
                    if (c == 0) {
                        break;
                    }

                    filename ~= cast(char) c;
                }

                log_ipc("DevFS::CreateFile(%s, %d, %d)", filename, owner_id, group_id);
                try { std.file.write("/home/zaydq/wii" ~ filename, new ubyte[0]); } catch (Exception e) {}
            } else if (ioctl == 0x5) {
                log_ipc("Who knows");
            } else if (ioctl == 0x6) {
                string filename = "";
                for (int i = 0; i < 0x40; i++) {
                    auto c = mem.paddr_read_u8(input_buffer + i);
                    if (c == 0) {
                        break;
                    }
                
                    filename ~= cast(char) c;
                }

                log_ipc("DevFS::Dipshit(%s)", filename);
                return cast(int) IPCError.ENOENT;
            } else {
                error_ipc("Unknown ioctl %d", ioctl);
            }

            return 0;
        }

        override void ioctlv(u32 request_paddr, int ioctl, int argcin, int argcio, u32 data_paddr) {
            log_ipc("DevFS::ioctlv(%d, %d, %d, %d)", ioctl, argcin, argcio, data_paddr);

            if (ioctl == 0x4) {
                if (argcin != 1) {
                    error_ipc("Invalid argcin %d", argcin);
                }

                if (argcio != 1) {
                    error_ipc("Invalid argcio %d", argcio);
                }

                // ReadDir
                u32 file_addr = mem.paddr_read_u32(data_paddr);

                string filename;
                for (int i = 0; i < 0x40; i++) {
                    auto c = mem.paddr_read_u8(file_addr + i);
                    if (c == 0) {
                        break;
                    }

                    filename ~= cast(char) c;
                }

                if (!std.file.dirEntries("/home/zaydq/wii" ~ filename, SpanMode.shallow).empty) {
                    error_ipc("handle this dipshit");
                }

                mem.paddr_write_u32(mem.paddr_read_u32(data_paddr + 0x8), 0);
            } else if (ioctl == 0xc) {
                u32 file_addr = mem.paddr_read_u32(data_paddr);

                string filename;
                for (int i = 0; i < 0x40; i++) {
                    auto c = mem.paddr_read_u8(file_addr + i);
                    if (c == 0) {
                        break;
                    }

                    filename ~= cast(char) c;
                }

                log_ipc("DevFS::DipshitGetUsage(%s)", filename);
            } else {
                error_ipc("Unknown ioctlv %d", ioctl);
            }

            ipc_response_queue.push_later(request_paddr, 0, 40_000);
        }
    }

    final class DevNetKdRequest : File {
        this() {
            super("/dev/net/kd/request");
        }

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            // if (ioctl == 7) {
            //     return;
            // } else {
            //     error_ipc("Unknown ioctl %d", ioctl);
            // }
            return 0;
        }
    }

    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;

        // find file for /dev/usb/oh1/57e/305
        auto usb_dev = cast(UsbDev57e305) get_file_by_name("/dev/usb/oh1/57e/305");
        usb_dev.usb_manager.connect_mem(mem);
    }

    File[] files;

    FileDescriptor fd_counter = 0;
    File[FileDescriptor] open_files;

    ubyte[256] settings_txt;
    void generate_settings_txt() {
        string stuff = "AREA=USA\n" ~
                       "MODEL=RVL-001(USA)\n" ~
                       "DVD=0\n" ~
                       "MPCH=0x7FFE\n" ~
                       "CODE=69\n" ~
                       "SERNO=11223344\n" ~
                       "VIDEO=NTSC\n" ~
                       "GAME=US";
        
        ubyte[256] data_buffer = new ubyte[256];

        for (size_t i = 0; i < stuff.length; i++) {
            settings_txt[i] = cast(ubyte) stuff[i];
        }

        for (size_t i = settings_txt.length; i < 256; i++) {
            settings_txt[i] = 0;
        }
    }

    final class PlayRec : File {
        u8[128] data;

        this() {
            super("/title/00000001/00000002/data/play_rec.dat");
        }

        int offset = 0;
        override int read(u8[] buffer, int size) {
            if (offset + size > data.length) {
                error_ipc("Read past end of file %s", path);
            }

            buffer[0 .. size] = data[offset .. offset + size];
            offset += size;

            return size;
        }

        override int seek(int offset, int whence) {
            if (whence == 0) {
                this.offset = offset;
            } else if (whence == 1) {
                this.offset += offset;
            } else if (whence == 2) {
                this.offset = cast(int) data.length + offset;
            } else {
                error_ipc("Invalid whence %d", whence);
            }

            return this.offset;
        }

        override int write(u8* buffer, int size) {
            // if (offset + size > data.length) {
            //     error_ipc("Write past end of file %s", path);
            // }

            // data[offset .. offset + size] = buffer[0 .. size];
            // offset += size;

            return size;
        }
    }

    final class DevStmImmediate : File {
        this() {
            super("/dev/stm/immediate");
        }

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            if (ioctl == 0x5001) {
                log_ipc("Set brightness to %d", mem.paddr_read_u32(input_buffer));
            } else {
                error_ipc("Unknown ioctl %d", ioctl);
            }
            return 0;
        }
    }

    final class UsbDev57e305 : File {
        USBManager usb_manager;

        this(IPCResponseQueue ipc_response_queue) {
            super("/dev/usb/oh1/57e/305");

            usb_manager = new USBManager(ipc_response_queue);
        }
        
        override void ioctlv(u32 request_paddr, int ioctl, int argcin, int argcio, u32 data_paddr) {
            log_ipc("UsbDev57e305::ioctlv(%x, %x, %x, %x)", ioctl, argcin, argcio, data_paddr);
            u32 addr = data_paddr;

            switch (ioctl) {
            case 0: {
                // control
                u8 bm_request_type = mem.paddr_read_u8(mem.paddr_read_u32(addr + 0));
                u8 b_request = mem.paddr_read_u8(mem.paddr_read_u32(addr + 8));

                // todo: make LE accessors
                u16 w_value = bswap(mem.paddr_read_u16(mem.paddr_read_u32(addr + 16)));
                u16 w_index = bswap(mem.paddr_read_u16(mem.paddr_read_u32(addr + 24)));
                u16 w_length = bswap(mem.paddr_read_u16(mem.paddr_read_u32(addr + 32)));

                u8[] data;
                for (int i = 0; i < w_length; i++) {
                    data ~= mem.paddr_read_u8(mem.paddr_read_u32(addr + 48) + i);
                }

                u8[] response = usb_manager.control_request(request_paddr, bm_request_type, b_request, w_value, w_index, w_length, data);
                
                break;
            }
            case 1: {
                // bulk
                u8 endpoint = mem.paddr_read_u8(mem.paddr_read_u32(addr + 0));
                u16 w_length = mem.paddr_read_u16(mem.paddr_read_u32(addr + 8)); 

                u8[] data;
                for (int i = 0; i < w_length; i++) {
                    data ~= mem.paddr_read_u8(mem.paddr_read_u32(addr + 16) + i);
                }

                u8[] response = usb_manager.bulk_request(request_paddr, endpoint, data);
                // for (int i = 0; i < response.length; i++) {
                //     mem.paddr_write_u8(mem.paddr_read_u32(addr + 16) + i, response[i]);
                // }

                break;
            }
            case 2: {
                // interrupt
                u8 endpoint = mem.paddr_read_u8(mem.paddr_read_u32(addr + 0));
                u16 w_length = mem.paddr_read_u16(mem.paddr_read_u32(addr + 8));     

                u8[] data;
                for (int i = 0; i < w_length; i++) {
                    data ~= mem.paddr_read_u8(mem.paddr_read_u32(addr + 16) + i);
                }

                u8[] response = usb_manager.interrupt_request(request_paddr, endpoint, data);
                // for (int i = 0; i < response.length; i++) {
                    // mem.paddr_write_u8(mem.paddr_read_u32(addr + 16) + i, response[i]);
                // }

                break;
            }
            default: error_ipc("Unknown ioctl %d", ioctl);
            }
        }
    }

    final class DevUsbVen : File {
        this() {
            super("/dev/usb/ven");
        }

        int num_device_change_callbacks = 0;

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            if (ioctl == 0) {
                mem.paddr_write_u32(output_buffer, 0x50001);
            } else if (ioctl == 1) {
                num_device_change_callbacks++;
                mem.paddr_write_u32(output_buffer, num_device_change_callbacks);
            } else if (ioctl == 6) {
                // yolo 
            } else {
                error_ipc("Unknown ven ioctl %d", ioctl);
            }
            return 0;
        }
    }

    final class DevUsbHid : File {
        this() {
            super("/dev/usb/hid");
        }

        override int ioctl(int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
            if (ioctl == 0) {
                mem.paddr_write_u32(output_buffer, 0x50001);
            } else if (ioctl == 1) {
                // yolo
            } else if (ioctl == 6) {
                mem.paddr_write_u32(output_buffer, 0x40001);
            } else {
                error_ipc("Unknown hid ioctl %d", ioctl);
            }
            return 0;
        }
    }

    DevES dev_es;
    DevFS dev_fs;

    alias IPCResponseQueue = IPC.IPCResponseQueue;
    IPCResponseQueue ipc_response_queue;

    this(IPCResponseQueue ipc_response_queue) {
        this.ipc_response_queue = ipc_response_queue;
        
        dev_es = new DevES();
        dev_fs = new DevFS();

        generate_settings_txt();

        files = [
            dev_es,
            dev_fs,
            new UsbDev57e305(this.ipc_response_queue),
            new DevStmImmediate(),
            new DevNetKdTime(),
            new DevNetKdRequest(),
            new EventHook(),
            new EncryptedBuffer("/title/00000001/00000002/data/setting.txt", settings_txt),
            new TitleState(),
            new NANDBootInfo(),
            new PlayRec(),
            new DevUsbVen(),
            new DevUsbHid()
        ];
    }

    void open(u32 paddr, string filename, OpenMode mode, int uid, int gid) {
        int result;
        
        if (mode > OpenMode.ReadWrite) {
            error_ipc("Invalid mode %d", mode);
        }

        log_ipc("IPC::Open(%s, %d, %d, %d)", filename, mode, uid, gid);

        FileDescriptor new_fd = fd_counter++;

        auto file = get_file_by_name(filename);
        if (file is null) {
            result = IPCError.ENOENT;
        } else {
            open_files[new_fd] = file;
            result = new_fd;
        }

        ipc_response_queue.push_later(paddr, new_fd, 40_000);
    }

    void close(u32 paddr, FileDescriptor fd) {
        log_ipc("IPC::Close(%d)", fd);

        int result;
        if (fd in open_files) {
            open_files[fd].close();
            result = IPCError.OK;
        } else {
            result = IPCError.ENOENT;
        }

        ipc_response_queue.push_later(paddr, result, 40_000);
    }

    void ioctl(u32 paddr, FileDescriptor fd, int ioctl, int input_buffer, int input_buffer_length, int output_buffer, int output_buffer_length) {
        log_ipc("IPC::Ioctl(%d, %d, %d, %d, %d, %d)", fd, ioctl, input_buffer, input_buffer_length, output_buffer, output_buffer_length);

        int result;
        if (fd in open_files) {
            result = open_files[fd].ioctl(ioctl, input_buffer, input_buffer_length, output_buffer, output_buffer_length);
        } else {
            result = IPCError.ENOENT;
        }

        ipc_response_queue.push_later(paddr, result, 40_000);
    }

    void ioctlv(u32 paddr, FileDescriptor fd, int ioctl, int argcin, int argcio, u32 data_paddr) {
        log_ipc("IPC::Ioctlv(%d, %d, %d, %d, %d)", fd, ioctl, argcin, argcio, data_paddr);

        int result;
        if (fd in open_files) {
            open_files[fd].ioctlv(paddr, ioctl, argcin, argcio, data_paddr);
        } else {
            result = IPCError.ENOENT;
            ipc_response_queue.push_later(paddr, result, 40_000);
        }
    }

    void read(u32 paddr, FileDescriptor fd, int size, u8[] buffer) {
        // log_ipc("IPC::Read(%d, %d, %x)", cast(int) fd, size, buffer);

        int result;
        if (fd in open_files) {
            auto file = open_files[fd];
            result = file.read(buffer, size);
        } else {
            result = IPCError.ENOENT;
        }

        u32 buffer_paddr = mem.paddr_read_u32(paddr + 0xC);
        if (result > 0) {
            for (int i = 0; i < size; i++) {
                if (fd == 4) {
                    log_ipc("    IOS::Read[%d]: %x", i, buffer[i]);
                }
                mem.paddr_write_u8(buffer_paddr + i, buffer[i]);
            }
        }

        ipc_response_queue.push_later(paddr, result, 40_000);
    }

    void seek(u32 paddr, FileDescriptor fd, int where, int whence) {
        log_ipc("IPC::Seek(%d, %d, %d)", fd, where, whence);

        int result;
        if (fd in open_files) {
            auto file = open_files[fd];
            result = file.seek(where, whence);
        } else {
            result = IPCError.ENOENT;
        }
     
        ipc_response_queue.push_later(paddr, result, 40_000);
    }

    void write(u32 paddr, FileDescriptor fd, int size, u8* buffer) {
        log_ipc("IPC::Write(%d, %d, %x)", fd, size, buffer);

        int result;
        if (fd in open_files) {
            auto file = open_files[fd];
            result = file.write(buffer, size);
        } else {
            result = IPCError.ENOENT;
        }

        ipc_response_queue.push_later(paddr, result, 40_000);
    }

    File get_file_by_name(string filename) {
        foreach (file; files) {
            if (file.path == filename) {
                return file;
            }
        }

        error_ipc("File not found: %s", filename);
        return null;
    }

    void load_sysconf(ubyte[] sysconf) {
        this.files ~= new DataFile("/shared2/sys/SYSCONF", sysconf);
    }

    void load_file_reader(FileReader file_reader) {
        this.files ~= new DiskDi(file_reader);
    }

    void set_title_id(u64 title_id) {
        dev_es.set_title_id(title_id);
        dev_fs.set_title_id(title_id);
    }
}