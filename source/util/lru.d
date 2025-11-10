module util.lru;

struct ClockCache(K, V, size_t Size) {
    struct Entry {
        K key;
        V value;
        bool valid;
        bool reference_bit;
    }
    
    Entry[Size] entries;
    size_t clock_hand;
    size_t count;
    
    size_t insert(K key) {
        foreach (i, ref entry; entries) {
            if (entry.valid && entry.key == key) {
                entry.reference_bit = true;
                return i;
            }
        }

        if (count < Size) {
            foreach (i, ref entry; entries) {
                if (!entry.valid) {
                    entry.key = key;
                    entry.valid = true;
                    entry.reference_bit = true;
                    count++;
                    return i;
                }
            }
        }

        while (true) {
            Entry* victim = &entries[clock_hand];
            size_t victim_index = clock_hand;
            clock_hand = (clock_hand + 1) % Size;

            if (!victim.reference_bit) {
                victim.key = key;
                victim.valid = true;
                victim.reference_bit = true;
                return victim_index;
            }

            victim.reference_bit = false;
        }
    }

    long lookup(K key) {
        foreach (i, ref entry; entries) {
            if (entry.valid && entry.key == key) {
                entry.reference_bit = true;
                return cast(long) i;
            }
        }

        return -1;
    }

    void clear() {
        foreach (ref entry; entries) {
            entry.valid = false;
        }

        clock_hand = 0;
        count = 0;
    }
}