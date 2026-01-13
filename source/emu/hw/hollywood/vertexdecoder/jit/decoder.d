module emu.hw.hollywood.vertexdecoder.jit.decoder;

import emu.hw.broadway.jit.emission.codeblocks;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.jit.code;
import emu.hw.hollywood.vertexdecoder.jit.page_table;
import emu.hw.hollywood.vertexdecoder.types;
import util.log;
import util.number;

alias VertexJitFunction = VertexDecodeResult function(const ubyte* stream,
                                                      Vertex* out_vertices);

struct VertexJitEntry {
    VertexJitFunction func;
    u64               key;
    int               func_size;
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
                                       ref VertexDecodeState state,
                                       Vertex* out_vertices,
                                       size_t max_vertices) {
        auto jit_key = create_jit_key(state);
        VertexJitEntry entry;
        bool found = cache.get(jit_key, entry);

        if (!found) {
            generate_and_store_stub(jit_key, state);
            bool inserted = cache.get(jit_key, entry);
            assert_vertex_jit(inserted, "failed to insert stub");
        }

        auto jit_func = entry.func;
        return jit_func(stream, out_vertices);
    }

    private void generate_and_store_stub(u64 key, ref VertexDecodeState state) {
        code.init();

        code.emit(state);

        ubyte[] bytes = code.get();
        auto func_ptr = codeblocks.put(cast(void*) bytes.ptr, bytes.length);
        cache.put(key, VertexJitEntry(cast(VertexJitFunction) func_ptr, key, cast(int) bytes.length));
    }

    private u64 create_jit_key(ref VertexDecodeState state) {
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
