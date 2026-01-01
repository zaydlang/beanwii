module util.perfect_bloom_filter_dict;

import util.bloom_filter;
import util.number;

struct Entry(T) {
    u64 key;
    T value;
}

final class PerfectBloomFilterDict(T) {
    private BloomFilter filter;
    private Entry!T[] entries;
    
    this(u32 filter_size = 8192, u32 num_hashes = 3) {
        filter = new BloomFilter(filter_size, num_hashes);
    }
    
    void set(u64 key, T value) {
        if (!filter.contains(key)) {
            filter.add(key);
        }
        
        for (size_t i = 0; i < entries.length; i++) {
            if (entries[i].key == key) {
                entries[i].value = value;
                return;
            }
        }
        
        entries ~= Entry!T(key, value);
    }
    
    bool get(u64 key, out T value) {
        if (!filter.contains(key)) {
            return false;
        }
        
        for (size_t i = 0; i < entries.length; i++) {
            if (entries[i].key == key) {
                value = entries[i].value;
                return true;
            }
        }
        
        return false;
    }
    
    void clear() {
        filter.clear();
        entries.length = 0;
    }
}