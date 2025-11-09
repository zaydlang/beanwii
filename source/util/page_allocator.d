module util.page_allocator;

import core.sys.posix.sys.mman;
import core.stdc.string;

struct PageAllocator(T) {
    private T* memory;
    private size_t capacity;
    private size_t used;
    private enum page_size = 4096 / T.sizeof;
    
    this(int dummy) {
        capacity = 0;
        used = 0;
    }
    
    T* allocate() {
        if (used >= capacity) {
            grow();
        }

        return &memory[used++];
    }
    
    void reset() {
        used = 0;
    }
    
    size_t length() const {
        return used;
    }
    
    ref T opIndex(size_t index) {
        return memory[index];
    }
    
    T* all() {
        return memory;
    }
    
    private void grow() {
        size_t new_capacity = capacity == 0 ? page_size : capacity * 2;
        size_t new_bytes = new_capacity * T.sizeof;
        
        void* new_memory = mmap(null, new_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        
        if (memory) {
            memcpy(new_memory, memory, capacity * T.sizeof);
            munmap(memory, capacity * T.sizeof);
        }
        
        memory = cast(T*) new_memory;
        capacity = new_capacity;
    }

}