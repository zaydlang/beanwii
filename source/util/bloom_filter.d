module util.bloom_filter;

import util.number;

final class BloomFilter {
    private u64[] bits;
    private u32 size;
    private u32 num_hashes;
    
    this(u32 size, u32 num_hashes) {
        this.size = size;
        this.num_hashes = num_hashes;
        this.bits = new u64[(size + 63) / 64];
    }
    
    void add(u64 value) {
        for (u32 i = 0; i < num_hashes; i++) {
            u32 hash = cast(u32)(hash_function(value, i) % size);
            u32 word_index = hash / 64;
            u32 bit_index = hash % 64;
            bits[word_index] |= (1UL << bit_index);
        }
    }
    
    bool contains(u64 value) {
        for (u32 i = 0; i < num_hashes; i++) {
            u32 hash = cast(u32) (hash_function(value, i) % size);
            u32 word_index = hash / 64;
            u32 bit_index = hash % 64;
            
            if ((bits[word_index] & (1UL << bit_index)) == 0) {
                return false;
            }
        }

        return true;
    }
    
    void clear() {
        bits[] = 0;
    }
    
    private u64 hash_function(u64 value, u32 seed) {
        value ^= seed;
        value ^= value >> 33;
        value *= 0xff51afd7ed558ccdUL;
        value ^= value >> 33;
        value *= 0xc4ceb9fe1a85ec53UL;
        value ^= value >> 33;
        return value;
    }
}