module emu.hw.broadway.jit.page_table;

import core.memory;
import emu.hw.broadway.jit.jit;
import util.bitop;
import util.log;
import util.number;

final class PageTable(T) {
    struct U {
        T entry;
        bool valid;
    }

    // We want entries from 0x80000000 to 0x9fffffff
    // This is 29 bits of information.
    // Lets split this as 7, 7, 7, 8
    
    U**** entries;

    this() {
        entries = cast(U****) GC.calloc(8 * 128);
    
        for (int i = 0; i < 128; i++) {
            entries[i] = null;
        }
    }

    void put(u32 address, T entry) {
        auto l1 = address.bits(22, 28);
        auto l2 = address.bits(15, 21);
        auto l3 = address.bits(8, 14);
        auto l4 = address.bits(0, 7);

        auto l1_entries = entries[l1];
        if (l1_entries == null) {
            entries[l1] = cast(U***) GC.calloc(8 * 128);
            l1_entries = entries[l1];
        }

        auto l2_entries = l1_entries[l2];
        if (l2_entries == null) {
            l1_entries[l2] = cast(U**) GC.calloc(8 * 128);
            l2_entries = l1_entries[l2];
        }

        auto l3_entries = l2_entries[l3];
        if (l3_entries == null) {
            l2_entries[l3] = cast(U*) GC.calloc(U.sizeof * 256);
            l3_entries = l2_entries[l3];
        }

        l3_entries[l4].valid = true;
        l3_entries[l4].entry = entry;
    }

    T* get_assume_has(u32 address) {
        if (!has(address)) {
            error_jit("PageTable: Address %x not found in page table", address);
        }

        auto l1 = address.bits(22, 28);
        auto l2 = address.bits(15, 21);
        auto l3 = address.bits(8, 14);
        auto l4 = address.bits(0, 7);

        auto l1_entries = entries[l1];
        auto l2_entries = l1_entries[l2];
        auto l3_entries = l2_entries[l3];

        return &l3_entries[l4].entry;
    }

    void remove(u32 address) {
        if (has(address)) {
            auto l1 = address.bits(22, 28);
            auto l2 = address.bits(15, 21);
            auto l3 = address.bits(8, 14);
            auto l4 = address.bits(0, 7);

            entries[l1][l2][l3][l4].valid = false;
        }
    }

    bool has(u32 address) {
        auto l1 = address.bits(22, 28);
        auto l2 = address.bits(15, 21);
        auto l3 = address.bits(8, 14);
        auto l4 = address.bits(0, 7);

        auto l1_entries = entries[l1];
        if (l1_entries == null) {
            return false;
        }

        auto l2_entries = l1_entries[l2];
        if (l2_entries == null) {
            return false;
        }

        auto l3_entries = l2_entries[l3];
        if (l3_entries == null) {
            return false;
        }

        auto entry = l3_entries[l4];
        return entry.valid;
    }

    void iterate_all(void delegate(u32 address, T entry) callback) {
        for (int l1 = 0; l1 < 128; l1++) {
            if (entries[l1] is null) continue;
            
            for (int l2 = 0; l2 < 128; l2++) {
                if (entries[l1][l2] is null) continue;
                
                for (int l3 = 0; l3 < 128; l3++) {
                    if (entries[l1][l2][l3] is null) continue;
                    
                    for (int l4 = 0; l4 < 256; l4++) {
                        if (entries[l1][l2][l3][l4].valid) {
                            u32 address = (l1 << 22) | (l2 << 15) | (l3 << 8) | l4;
                            address |= 0x80000000; // Add base offset for PowerPC memory layout
                            callback(address, entries[l1][l2][l3][l4].entry);
                        }
                    }
                }
            }
        }
    }
}