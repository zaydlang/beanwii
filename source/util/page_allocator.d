module util.page_allocator;

import core.sys.posix.sys.mman;
import core.stdc.string;
import util.log;

struct PageAllocator(T, bool ENFORCE_CONSECUTIVE = true) {
    private T* memory;
    private size_t capacity;
    private size_t used;
    private enum page_size = 4096 / T.sizeof;
    private bool did_reallocate = false;
    
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
    
    T[] allocate_array(size_t count) {
        while (used + count > capacity) {
            grow();
        }
        
        T* start = &memory[used];
        used += count;
        return start[0..count];
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
    
    bool check_and_clear_reallocate_flag() {
        bool result = did_reallocate;
        did_reallocate = false;
        return result;
    }
    
    private void grow() {
        size_t new_capacity = capacity == 0 ? page_size : capacity * 2;
        size_t new_bytes = new_capacity * T.sizeof;
        
        void* new_memory = mmap(null, new_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        
        static if (ENFORCE_CONSECUTIVE) {
            if (memory) {
                memcpy(new_memory, memory, used * T.sizeof);
                munmap(memory, capacity * T.sizeof);
            }
        } else {
            used = 0;  // Reset since we're not copying data
            did_reallocate = true;
        }
        
        memory = cast(T*) new_memory;
        capacity = new_capacity;
    }

}