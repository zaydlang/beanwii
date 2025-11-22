module emu.hw.memory.strategy.hardware_accelerated_mem.virtualmemory;

version (linux) {
} else {
    static assert(false, "VirtualMemoryManager is only implemented for Linux systems.");
}

import core.sys.posix.signal;
import core.sys.posix.sys.mman;
import core.sys.posix.unistd;
import std.stdio;
import util.array;
import util.log;
import util.number;

extern(C) {
    int memfd_create(const char *name, uint flags);
}

alias MemoryRegionDescriptor = int;

struct VirtualMemoryRegion {
    string name;
    MemoryRegionDescriptor descriptor;
    u64 size;
}

struct VirtualMemorySpace {
    string name;
    void* base_address;
    u64 size;
}

final class VirtualMemoryManager {
    private VirtualMemorySpace[] memory_spaces;

    this() {
        sigaction_t sa;
        sa.sa_flags = SA_SIGINFO;
        sa.sa_sigaction = &virtual_memory_segfault_handler;
        sigaction(SIGSEGV, &sa, null);

        _virtual_memory_manager = this;
    }

    VirtualMemorySpace* create_memory_space(string name, u64 size) {
        VirtualMemorySpace space = VirtualMemorySpace(
            name,
            mmap(null, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0),
            size
        );

        this.memory_spaces ~= space;

        return &this.memory_spaces[$ - 1];
    }

    VirtualMemoryRegion* create_memory_region(string name, u64 size) {
        MemoryRegionDescriptor descriptor = memfd_create(cast(char*) name, 0);
        ftruncate(descriptor, size);

        return new VirtualMemoryRegion(
            name,
            descriptor,
            size
        );
    }

    void unmap(VirtualMemorySpace* space, u64 address, u64 size) {
        void* host_address = this.to_host_address(space, address);
        int unmap_error = munmap(host_address, size);
        if (unmap_error < 0) {
            perror("unmap");
            error_memory("Failed to unmap memory region");
            assert(0);
        }

        mmap(host_address, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    }

    void map(VirtualMemorySpace* space, VirtualMemoryRegion* memory_region, u64 address) {
        map_generic(space, memory_region, address, memory_region.size);
    }

    void map_with_length(VirtualMemorySpace* space, VirtualMemoryRegion* memory_region, u64 address, u64 size) {
        map_generic(space, memory_region, address, size);
    }

    void* to_host_address(VirtualMemorySpace* space, u64 address) {
        return cast(void*) (space.base_address + address);
    }

    u64 to_guest_address(VirtualMemorySpace* space, void* address) {
        return cast(u64) (address - space.base_address);
    }

    T read(T)(VirtualMemorySpace* space, u64 address) {
        return *(cast(T*) this.to_host_address(space, address));
    }

    T read_be(T)(VirtualMemorySpace* space, u64 address) {
        return (cast(u8*) space.base_address).read_be!T(address);
    }

    void write(T)(VirtualMemorySpace* space, u64 address, T value) {
        *(cast(T*) this.to_host_address(space, address)) = value;
    }

    void write_be(T)(VirtualMemorySpace* space, u64 address, T value) {
        (cast(u8*) space.base_address).write_be!T(address, value);
    }

    bool in_range(VirtualMemorySpace* space, void* address) {
        return address >= space.base_address && address < space.base_address + space.size;
    }

    private void map_generic(VirtualMemorySpace* space, VirtualMemoryRegion* memory_region, u64 address, u64 size) {
        void* host_address = this.to_host_address(space, address);

        int unmap_error = munmap(host_address, size);
        if (unmap_error < 0) {
            perror("unmap");
            error_memory("Failed to unmap memory region");
            assert(0);
        }

        void* map_error = mmap(host_address, size, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_SHARED, memory_region.descriptor, 0);
        if (cast(u64) map_error < 0) {
            error_memory("Failed to map memory region");
            assert(0);
        }
    }
}

__gshared VirtualMemoryManager _virtual_memory_manager;

extern(C) 
private void virtual_memory_segfault_handler(int signum, siginfo_t* info, void* context) {
    void* fault_addr = info.si_addr;
    
    for (size_t i = 0; i < _virtual_memory_manager.memory_spaces.length; i++) {
        VirtualMemorySpace* space = &_virtual_memory_manager.memory_spaces[i];
        if (_virtual_memory_manager.in_range(space, fault_addr)) {
            u64 guest_addr = _virtual_memory_manager.to_guest_address(space, fault_addr);
            error_memory("Invalid memory access at guest 0x%08X", guest_addr);
            return;
        }
    }
    
    error_memory("Invalid memory access at host 0x%08X", cast(u64) fault_addr);
}