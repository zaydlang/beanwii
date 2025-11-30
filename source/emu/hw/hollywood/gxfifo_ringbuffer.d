module emu.hw.hollywood.gxfifo_ringbuffer;

import core.sys.posix.sys.mman;
import core.sys.posix.unistd;
import core.stdc.string;
import util.bitop;
import util.log;

extern(C) int memfd_create(const char* name, uint flags);

final class GXFifoRingBuffer {
    ubyte* buffer;
    size_t read_ptr;
    size_t write_ptr;
    size_t buffer_size;
    size_t page_size;
    int fd;

    this(size_t num_pages) {
        page_size = 4096;
        buffer_size = num_pages * page_size;
        
        fd = memfd_create("gxfifo_ring", 0);
        if (fd == -1) {
            error_hollywood("Failed to create memfd");
        }
        
        if (ftruncate(fd, buffer_size) == -1) {
            error_hollywood("Failed to resize memfd");
        }
        
        void* mem = mmap(null, buffer_size * 2, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (mem == MAP_FAILED) {
            error_hollywood("Failed to allocate virtual address space");
        }
        
        if (mmap(mem, buffer_size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, 0) == MAP_FAILED) {
            error_hollywood("Failed to map first buffer");
        }
        
        if (mmap(cast(void*) (cast(ubyte*) mem + buffer_size), buffer_size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, 0) == MAP_FAILED) {
            error_hollywood("Failed to map duplicate buffer");
        }
        
        buffer = cast(ubyte*) mem;
        read_ptr = 0;
        write_ptr = 0;
    }
    
    bool add(T)(T value) {
        static if (T.sizeof == 1) {
            buffer[write_ptr] = value;
        } else static if (T.sizeof == 2) {
            ushort swapped = bswap(cast(ushort) value);
            memcpy(buffer + write_ptr, &swapped, 2);
        } else static if (T.sizeof == 4) {
            uint swapped = bswap(cast(uint) value);
            memcpy(buffer + write_ptr, &swapped, 4);
        } else static if (T.sizeof == 8) {
            ulong swapped = bswap(cast(ulong) value);
            memcpy(buffer + write_ptr, &swapped, 8);
        } else {
            static assert(false, "Unsupported type size");
        }
        
        write_ptr += T.sizeof;
        
        log_hollywood("GXFifoRingBuffer: Added %d bytes at position %u", T.sizeof, write_ptr - T.sizeof);
        log_hollywood("GXFifoRingBuffer: New write_ptr is %u", write_ptr);
        log_hollywood("watermark check: %s", write_ptr >= buffer_size - 32 ? "true" : "false");
        return write_ptr >= buffer_size - 32;
    }
    
    T remove(T)() {
        T value;
        
        static if (T.sizeof == 1) {
            value = buffer[read_ptr];
        } else static if (T.sizeof == 2) {
            ushort raw_value;
            memcpy(&raw_value, buffer + read_ptr, 2);
            value = cast(T) bswap(raw_value);
        } else static if (T.sizeof == 4) {
            uint raw_value;
            memcpy(&raw_value, buffer + read_ptr, 4);
            value = cast(T) bswap(raw_value);
        } else static if (T.sizeof == 8) {
            ulong raw_value;
            memcpy(&raw_value, buffer + read_ptr, 8);
            value = cast(T) bswap(raw_value);
        } else {
            static assert(false, "Unsupported type size");
        }
        
        read_ptr += T.sizeof;
        
        return value;
    }
    
    size_t get_size() {
        if (write_ptr >= read_ptr) {
            return write_ptr - read_ptr;
        } else {
            return (buffer_size - read_ptr) + write_ptr;
        }
    }
    
    void clear() {
        read_ptr = 0;
        write_ptr = 0;
    }
    
    void wrap_pointers() {
        if (write_ptr >= buffer_size) {
            write_ptr -= buffer_size;
        }
        
        if (read_ptr >= buffer_size) {
            read_ptr -= buffer_size;
        }

        log_hollywood("GXFifoRingBuffer: Wrapped pointers - read_ptr: %u, write_ptr: %u", read_ptr, write_ptr);
    }
}