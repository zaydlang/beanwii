module emu.hw.broadway.jit.emission.codeblocks;

import core.stdc.string; 
import core.sys.posix.sys.mman;
import util.log;

final class CodeBlockTracker {
    struct Allocation {
        void* page;
        size_t capacity;
    }

    Allocation[] allocations;

    private void add_new_allocation() {
        void* new_ptr = mmap(null, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        allocations ~= Allocation(new_ptr, 0x4000);
    }

    void* put(void* code, size_t length) {
        assert(length <= 0x4000);

        if (allocations.length == 0) {
            add_new_allocation();
        }

        if (allocations[$ - 1].capacity < length) {
            add_new_allocation();
        }

        void* ptr = &allocations[$ - 1].page[0x4000 - allocations[$ - 1].capacity];
        memcpy(ptr, code, length);
        allocations[$ - 1].capacity -= length;
    
        return ptr;
    }
}
