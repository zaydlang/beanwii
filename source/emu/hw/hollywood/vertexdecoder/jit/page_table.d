module emu.hw.hollywood.vertexdecoder.jit.page_table;

import util.log;
import util.number;

struct PageTableEntry(T) {
    u64  key;
    T    value;
    bool valid;
}

/// Minimal open-addressed page table used by the vertex JIT cache.
final class PageTable(T, size_t NumBuckets = 512) {
    private alias Entry = PageTableEntry!T;

    Entry[NumBuckets] entries;

    private size_t start_bucket(u64 key) {
        return cast(size_t) (key % NumBuckets);
    }

    private Entry* find(u64 key) {
        size_t start = start_bucket(key);

        foreach (i; 0 .. NumBuckets) {
            size_t idx = (start + i) % NumBuckets;
            Entry* entry = &entries[idx];

            if (!entry.valid) {
                return null;
            }

            if (entry.key == key) {
                return entry;
            }
        }

        return null;
    }

    bool get(u64 key, ref T out_value) {
        auto entry = find(key);
        if (entry is null) {
            return false;
        }

        out_value = entry.value;
        return true;
    }

    void put(u64 key, T value) {
        size_t start = start_bucket(key);
        Entry* free_slot = null;

        foreach (i; 0 .. NumBuckets) {
            size_t idx = (start + i) % NumBuckets;
            Entry* entry = &entries[idx];

            if (entry.valid && entry.key == key) {
                entry.value = value;
                return;
            }

            if (!entry.valid) {
                free_slot = entry;
                break;
            }
        }

        if (free_slot is null) {
            free_slot = &entries[start];
        }

        *free_slot = Entry(key, value, true);
    }

    void clear() {
        foreach (ref entry; entries) {
            entry.valid = false;
        }
    }
}
