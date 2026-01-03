module test.hollywood.vertexdecoder.test;

import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.interpreter.decoder;
import emu.hw.hollywood.vertexdecoder.types;
import emu.hw.memory.strategy.memstrategy;
import std.math : fabs;
import util.force_cast;
import util.number;

/// Lightweight harness so the same cases can be pointed at the interpreter or the JIT.
struct VertexDecodeHarness {
    Mem mem;
    VertexDecodeState state;

    static VertexDecodeHarness make() {
        VertexDecodeHarness h;
        h.mem = new Mem();
        h.state.mem = h.mem;
        h.state.current_vat = 0;
        h.state.number_of_expected_vertices = 0;
        h.state.bytes_per_vertex = 0;

        foreach (i; 0 .. h.state.array_bases.length) {
            h.state.array_bases[i] = 0;
            h.state.array_strides[i] = 0;
        }

        foreach (i; 0 .. h.state.color_configs.length) {
            h.state.color_configs[i].material_src = MaterialSource.FromVertex;
            h.state.color_global[i] = [1.0f, 1.0f, 1.0f, 1.0f];
        }

        return h;
    }

    void set_position(VertexAttributeLocation location, CoordFormat format, int count = 3, int shift = 0) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];
        vcd.position_location = location;
        vat.position_format = format;
        vat.position_count = count;
        vat.position_shift = shift;
    }

    void set_position_matrix(VertexAttributeLocation location) {
        state.vertex_descriptors[state.current_vat].position_normal_matrix_location = location;
    }

    void set_color(int idx, VertexAttributeLocation location, ColorFormat format, int count = 4, MaterialSource src = MaterialSource.FromVertex) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];
        vcd.color_location[idx] = location;
        vat.color_format[idx] = format;
        vat.color_count[idx] = count;
        state.color_configs[idx].material_src = src;
    }

    void set_color_global(int idx, float[4] value) {
        state.color_global[idx] = value;
    }

    void set_texcoord(int idx, VertexAttributeLocation location, CoordFormat format, int count = 2, int shift = 0) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];
        vcd.texcoord_location[idx] = location;
        vat.texcoord_format[idx] = format;
        vat.texcoord_count[idx] = count;
        vat.texcoord_shift[idx] = shift;
    }

    void set_array(int idx, u32 base, u32 stride) {
        state.array_bases[idx] = base;
        state.array_strides[idx] = stride;
    }

    void write_array_bytes(int idx, u32 base, ubyte[] data, u32 stride) {
        set_array(idx, base, stride);
        foreach (i, b; data) {
            mem.physical_write_u8(base + cast(u32) i, b);
        }
    }

    /// Decode using whichever decoder instance is provided (interpreter now, JIT later).
    Vertex[] decode(D)(auto ref D decoder, const ubyte[] stream, size_t expected_vertices) {
        state.number_of_expected_vertices = cast(int) expected_vertices;
        auto decoded = new Vertex[expected_vertices];
        auto result = decoder.decode_vertices(stream.ptr, stream.length, state, decoded.ptr, decoded.length);
        return decoded[0 .. result.vertices_emitted];
    }
}

enum float VERTEX_EPS = 1e-5f;

void assert_close(float actual, float expected) {
    assert(fabs(actual - expected) <= VERTEX_EPS);
}

void assert_vertex_matches(Vertex actual,
                           Vertex expected,
                           VertexDescriptor* vcd,
                           VertexAttributeTable* vat) {

    if (vcd.position_location != VertexAttributeLocation.NotPresent) {
        int count = vat.position_count == 2 ? 2 : 3;
        foreach (i; 0 .. count) {
            assert_close(actual.position[i], expected.position[i]);
        }
        if (vat.position_count == 2) {
            assert_close(actual.position[2], expected.position[2]);
        }
    }

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        assert(actual.position_matrix_index == expected.position_matrix_index);
    }

    foreach (c; 0 .. 2) {
        if (vcd.color_location[c] != VertexAttributeLocation.NotPresent) {
            int components = vat.color_count[c] == 3 ? 3 : 4;
            foreach (i; 0 .. components) {
                assert_close(actual.color[c][i], expected.color[c][i]);
            }
        }
    }

    foreach (t; 0 .. 8) {
        if (vcd.texcoord_location[t] != VertexAttributeLocation.NotPresent) {
            int components = vat.texcoord_count[t] == 1 ? 1 : 2;
            foreach (i; 0 .. components) {
                assert_close(actual.texcoord[t][i], expected.texcoord[t][i]);
            }
        }
    }
}

void assert_vertices_match(Vertex[] actual,
                           Vertex[] expected,
                           ref VertexDecodeState state) {
    assert(actual.length == expected.length, "vertex count mismatch");
    auto vcd = &state.vertex_descriptors[state.current_vat];
    auto vat = &state.vats[state.current_vat];
    foreach (i; 0 .. actual.length) {
        assert_vertex_matches(actual[i], expected[i], vcd, vat);
    }
}

/// Fluent builder for expected vertices to keep tests terse.
struct VertexBuilder {
    Vertex v;

    ref VertexBuilder position(float x, float y, float z = 0) {
        v.position = [x, y, z];
        return this;
    }

    ref VertexBuilder matrix_index(int idx) {
        v.position_matrix_index = idx;
        return this;
    }

    ref VertexBuilder color(int idx, float r, float g, float b, float a) {
        v.color[idx] = [r, g, b, a];
        return this;
    }

    ref VertexBuilder texcoord(int idx, float s, float t = 0) {
        v.texcoord[idx][0] = s;
        v.texcoord[idx][1] = t;
        return this;
    }

    Vertex build() {
        return v;
    }
}

VertexBuilder vertex() {
    return VertexBuilder();
}

/// Small fluent helper for building BE vertex streams.
struct StreamBuilder {
    ubyte[] bytes;

    ref StreamBuilder stream_add_u8(u8 v) {
        bytes ~= v;
        return this;
    }

    ref StreamBuilder stream_add_u16_be(u16 v) {
        bytes ~= cast(ubyte) (v >> 8);
        bytes ~= cast(ubyte) (v & 0xFF);
        return this;
    }

    ref StreamBuilder stream_add_u32_be(u32 v) {
        bytes ~= cast(ubyte) (v >> 24);
        bytes ~= cast(ubyte) ((v >> 16) & 0xFF);
        bytes ~= cast(ubyte) ((v >> 8) & 0xFF);
        bytes ~= cast(ubyte) (v & 0xFF);
        return this;
    }

    ref StreamBuilder stream_add_s16_be(short v) {
        return stream_add_u16_be(cast(u16) v);
    }

    ref StreamBuilder stream_add_float(float f) {
        return stream_add_u32_be(force_cast!u32(f));
    }

    ubyte[] finish() {
        return bytes;
    }
}

@("vertex_decoder interpreter direct_position_dequantizes_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexInterpreterDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.F32, 3, 1);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_float(2.0f)   // -> 1.0 after shift
                .stream_add_float(-4.0f)  // -> -2.0 after shift
                .stream_add_float(0.5f)   // -> 0.25 after shift
                .finish(),
            1),
        [
            vertex().position(1.0f, -2.0f, 0.25f).build(),
        ],
        harness.state);
}

@("vertex_decoder interpreter indexed_positions_u8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexInterpreterDecoder();

    harness.set_position(VertexAttributeLocation.Indexed8Bit, CoordFormat.U8, 3, 0);
    // Two vertices laid out with stride 3 at array index 0.
    ubyte[] array_data = [1, 2, 3, 4, 5, 6];
    harness.write_array_bytes(0, 0x1000, array_data, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00)
                .stream_add_u8(0x01)
                .finish(), // indices into the position array
            2),
        [
            vertex().position(1.0f, 2.0f, 3.0f).build(),
            vertex().position(4.0f, 5.0f, 6.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder interpreter color_respects_material_source_global")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexInterpreterDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGBA8888, 4, MaterialSource.FromGlobal);
    harness.set_color_global(0, [0.1f, 0.2f, 0.3f, 0.4f]);

    // Incoming color data should be ignored in favor of the global value.
    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u32_be(0xAABBCCDD)
                .finish(),
            1),
        [
            vertex().color(0, 0.1f, 0.2f, 0.3f, 0.4f).build(),
        ],
        harness.state);
}

@("vertex_decoder interpreter indexed_color_rgba8888")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexInterpreterDecoder();

    harness.set_color(0, VertexAttributeLocation.Indexed8Bit, ColorFormat.RGBA8888, 4, MaterialSource.FromVertex);
    harness.write_array_bytes(2, 0x1100, [0x10, 0x20, 0x30, 0x40], 4);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00) // color index 0
                .finish(),
            1),
        [
            vertex().color(0,
                0x10 / 255.0f,
                0x20 / 255.0f,
                0x30 / 255.0f,
                0x40 / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder interpreter texcoord_direct_shifted_s16")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexInterpreterDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.S16, 2, 1);

    // Values: 4 and -4, then divide by 2 because shift=1.
    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_s16_be(4)
                .stream_add_s16_be(-4)
                .finish(),
            1),
        [
            vertex().texcoord(0, 2.0f, -2.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder interpreter position_matrix_index_present_and_absent")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexInterpreterDecoder();

    harness.set_position_matrix(VertexAttributeLocation.Direct);
    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.U8, 1, 0);

    auto stream_with_index = StreamBuilder()
        .stream_add_u8(0x05) // matrix index
        .stream_add_u8(0x0A) // position data
        .finish();

    assert_vertices_match(
        harness.decode(decoder, stream_with_index, 1),
        [
            vertex().position(10.0f, 0, 0).matrix_index(5).build(),
        ],
        harness.state);

    // Same setup but no matrix index should produce -1.
    harness.set_position_matrix(VertexAttributeLocation.NotPresent);
    assert_vertices_match(
        harness.decode(decoder, stream_with_index[1 .. $], 1),
        [
            vertex().position(10.0f, 0, 0).matrix_index(-1).build(),
        ],
        harness.state);
}
