module emu.hw.broadway.jit.emission.codeblocks;

import core.stdc.string; 
import core.sys.posix.sys.mman;
import util.log;
import util.page_allocator;

final class CodeBlockTracker {
    struct Allocation {
        void* page;
        size_t capacity;
    }

    PageAllocator!Allocation allocations;
    
    this() {
        allocations = PageAllocator!Allocation(0);
    }

    private void add_new_allocation() {
        void* new_ptr = mmap(null, 0x40000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        Allocation* alloc = allocations.allocate();
        alloc.page = new_ptr;
        alloc.capacity = 0x40000;
    }

    void* put(void* code, size_t length) {
        assert(length <= 0x40000);

        if (allocations.length == 0) {
            add_new_allocation();
        }

        if (allocations[allocations.length - 1].capacity < length) {
            // mprotect(allocations[allocations.length - 1].page, 0x40000, PROT_READ | PROT_EXEC);
            add_new_allocation();
        }

        void* ptr = &allocations[allocations.length - 1].page[0x40000 - allocations[allocations.length - 1].capacity];
        memcpy(ptr, code, length);
        allocations[allocations.length - 1].capacity -= length;
    
        return ptr;
    }
}
