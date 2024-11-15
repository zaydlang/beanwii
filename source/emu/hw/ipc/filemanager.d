module emu.hw.ipc.filemanager;

import emu.hw.ipc.error;
import std.conv;
import util.log;
import util.number;

alias FileDescriptor = int;

enum OpenMode {
    NoAccess  = 0,
    Read      = 1,
    Write     = 2,
    ReadWrite = 3
}

class File {
    string path;

    this(string path) {
        this.path = path;
    }

    void ioctl(int input_argc, int io_argc, int data_paddr) {
        error_ipc("ioctl not implemented for %s", path);
    }

    int read(u8* buffer, int size) {
        error_ipc("read not implemented for %s", path);
        return 0;
    }

    void close() {}
}

final class DataFile : File {
    ubyte[] data;

    this(string path, ubyte[] data) {
        super(path);
        this.data = data;
    }

    int offset = 0;

    override int read(u8* buffer, int size) {
        if (offset + size > data.length) {
            error_ipc("Read past end of file %s", path);
        }

        buffer[0 .. size] = data[offset .. offset + size];
        offset += size;

        return size;
    }
}

final class EventHook : File {
    this() {
        super("/dev/stm/eventhook");
    }

    override void ioctl(int input_argc, int io_argc, int data_paddr) {
        // this only matters for resetting the wii
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
    override int read(u8* buffer, int size) {
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
    override int read(u8* buffer, int size) {
        if (offset + size > StateFlags.sizeof) {
            error_ipc("Read past end of file %s", path);
        }

        buffer[0 .. size] = data[offset .. offset + size];
        offset += size;

        return size;
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
    override int read(u8* buffer, int size) {
        if (offset + size > NANDBootInfoInner.sizeof) {
            error_ipc("Read past end of file %s", path);
        }

        buffer[0 .. size] = data[offset .. offset + size];
        offset += size;

        return size;
    }
}

final class FileManager {
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

    this() {
        generate_settings_txt();

        files = [
            new File("/dev/es"),
            new File("/dev/stm/immediate"),
            new EventHook(),
            new EncryptedBuffer("/title/00000001/00000002/data/setting.txt", settings_txt),
            new TitleState(),
            new NANDBootInfo()
        ];
    }
    int open(string filename, OpenMode mode, int uid, int gid) {
        if (mode > OpenMode.ReadWrite) {
            error_ipc("Invalid mode %d", mode);
            return IPCError.EINVAL;
        }

        log_ipc("IPC::Open(%s, %d, %d, %d)", filename, mode, uid, gid);

        FileDescriptor new_fd = fd_counter++;

        auto file = get_file_by_name(filename);
        if (file is null) {
            return IPCError.ENOENT;
        }

        open_files[new_fd] = file;

        return new_fd;
    }

    int close(FileDescriptor fd) {
        log_ipc("IPC::Close(%d)", fd);

        if (fd in open_files) {
            open_files[fd].close();
            return IPCError.OK;
        } else {
            return IPCError.ENOENT;
        }
    }

    int ioctl(FileDescriptor fd, int input_argc, int io_argc, int data_paddr) {
        log_ipc("IPC::Ioctl(%d, %d, %d, %d)", fd, input_argc, io_argc, data_paddr);

        if (fd in open_files) {
            open_files[fd].ioctl(input_argc, io_argc, data_paddr);
            return IPCError.OK;
        } else {
            return IPCError.ENOENT;
        }
    }

    int read(FileDescriptor fd, int size, u8* buffer) {
        log_ipc("IPC::Read(%d, %d, %x)", fd, size, buffer);

        if (fd in open_files) {
            auto file = open_files[fd];
            return file.read(buffer, size);
        } else {
            return IPCError.ENOENT;
        }
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
}