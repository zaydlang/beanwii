module emu.hw.hollywood.vertexdecoder.jit.decoder;

import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.jit.code;
import emu.hw.hollywood.vertexdecoder.jit.page_table;
import emu.hw.hollywood.vertexdecoder.types;
import util.log;
import util.number;

struct ArrayInfo {
    ulong[16] host_bases;  // pre-resolved host pointers
    u32[16]   strides;
}

alias VertexJitFunction = extern(C) void function(const ubyte* stream, Vertex* out_vertices, const ArrayInfo* array_info);

struct VertexJitEntry {
    VertexJitFunction func;
    u64               key;
    int               func_size;
    DestFormat        dest_format;
}

final class VertexJitDecoder {
    private PageTable!VertexJitEntry cache;
    private Code                     code;
    private CodeBlockTracker         codeblocks;

    this() {
        cache = new PageTable!VertexJitEntry();
        code = new Code();
        codeblocks = new CodeBlockTracker();
    }

    VertexDecodeResult decode_vertices(const ubyte* stream,
                                       size_t /*length*/,
                                       ref VertexFormat state,
                                       Vertex* out_vertices,
                                       size_t max_vertices) {
        auto jit_key = create_jit_key(state);
        VertexJitEntry entry;
        bool found = cache.get(jit_key, entry);

        if (!found) {
            generate_and_store_func(jit_key, state);
            bool inserted = cache.get(jit_key, entry);
            assert_vertex_jit(inserted, "failed to insert stub");
        }

        auto jit_func = entry.func;

        ArrayInfo array_info;
        foreach (i; 0 .. 16) {
            if (state.array_bases[i] != 0)
                array_info.host_bases[i] = cast(ulong) state.mem.translate_address(state.array_bases[i]);
            array_info.strides[i] = state.array_strides[i];
        }

        jit_func(stream, out_vertices, &array_info);
        return VertexDecodeResult(cast(uint) state.number_of_expected_vertices, entry.dest_format);
    }

    private void generate_and_store_func(u64 key, ref VertexFormat state) {
        code.init();

        auto dest_format = code.emit(state);

        ubyte[] bytes = code.get();
        auto func_ptr = codeblocks.put(cast(void*) bytes.ptr, bytes.length);
        cache.put(key, VertexJitEntry(cast(VertexJitFunction) func_ptr, key, cast(int) bytes.length, dest_format));
    }

    private u64 create_jit_key(ref VertexFormat state) {
        auto vcd = state.vertex_descriptors[state.current_vat];
        auto vat = state.vats[state.current_vat];
        return hash_descriptor(vcd, vat);
    }

    private u64 hash_descriptor(ref VertexDescriptor vcd, ref VertexAttributeTable vat) {
        u64 h = 0xcbf29ce484222325;

        void mix(u64 value) {
            h ^= value;
            h *= 0x100000001b3;
        }

        mix(vcd.raw_vcd_lo);
        mix(vcd.raw_vcd_hi);
        mix(vat.raw_vat_a);
        mix(vat.raw_vat_b);
        mix(vat.raw_vat_c);

        return h;
    }
}
