module test.hollywood.vertexdecoder.test;

import consolecolors;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.interpreter.decoder;
import emu.hw.hollywood.vertexdecoder.jit.decoder;
import emu.hw.hollywood.vertexdecoder.types;
import emu.hw.memory.strategy.memstrategy;
import std.format : format;
import std.math : fabs;
import util.force_cast;
import util.number;

struct VertexDecodeHarness {
    Mem mem;
    VertexFormat state;

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

    void set_normal(VertexAttributeLocation location, NormalFormat format, int count = 3, int shift = 0) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];
        vcd.normal_location = location;
        vat.normal_format = format;
        vat.normal_count = count;
        vat.normal_shift = shift;
    }

    void set_color(int idx, VertexAttributeLocation location, ColorFormat format, int count = 4) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];
        vcd.color_location[idx] = location;
        vat.color_format[idx] = format;
        vat.color_count[idx] = count;
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
        auto decoded_raw = new ubyte[Vertex.sizeof * expected_vertices];
        auto result = decoder.decode_vertices(
            stream.ptr,
            stream.length,
            state,
            cast(Vertex*) decoded_raw.ptr,
            expected_vertices);
        auto vat = &state.vats[state.current_vat];
        return materialize_vertices(decoded_raw, result.dest_format, result.vertices_emitted, vat);
    }

    Vertex[] decode_with_max(D)(auto ref D decoder, const ubyte[] stream, size_t expected_vertices, size_t max_vertices) {
        state.number_of_expected_vertices = cast(int) expected_vertices;
        auto decoded_raw = new ubyte[Vertex.sizeof * max_vertices];
        auto result = decoder.decode_vertices(
            stream.ptr,
            stream.length,
            state,
            cast(Vertex*) decoded_raw.ptr,
            max_vertices);
        auto vat = &state.vats[state.current_vat];
        return materialize_vertices(decoded_raw, result.dest_format, result.vertices_emitted, vat);
    }
}

enum float VERTEX_EPS = 1e-5f;

bool close_enough(float actual, float expected) {
    return fabs(actual - expected) <= VERTEX_EPS;
}

string format_f32(float value) {
    return format("%.6f", value);
}

string colorize_value(string text, bool mismatch, bool expected) {
    if (!mismatch) {
        return text;
    }
    return expected ? "<lgreen>" ~ text ~ "</lgreen>" : "<lred>" ~ text ~ "</lred>";
}

void print_vec(string label,
               const(float)[] actual,
               const(float)[] expected,
               const(bool)[] diff,
               int count) {
    cwritef("Expected %s:", label);
    foreach (i; 0 .. count) {
        cwrite(" ");
        cwrite(colorize_value(format_f32(expected[i]), diff[i], true));
    }
    cwriteln("");

    cwritef("Actual   %s:", label);
    foreach (i; 0 .. count) {
        cwrite(" ");
        cwrite(colorize_value(format_f32(actual[i]), diff[i], false));
    }
    cwriteln("");
}

void print_int(string label, int actual, int expected, bool mismatch) {
    cwritefln("Expected %s: %s", label, colorize_value(format("%d", expected), mismatch, true));
    cwritefln("Actual   %s: %s", label, colorize_value(format("%d", actual), mismatch, false));
}

float read_f32(const ubyte[] buffer, size_t offset) {
    auto bits = *cast(const u32*) (buffer.ptr + offset);
    return force_cast!float(bits);
}

int read_s32(const ubyte[] buffer, size_t offset) {
    return *cast(const int*) (buffer.ptr + offset);
}

Vertex[] materialize_vertices(const ubyte[] buffer,
                              ref DestFormat format,
                              size_t count,
                              VertexAttributeTable* vat) {
    Vertex[] vertices = new Vertex[count];
    if (count == 0) {
        return vertices;
    }

    assert(format.stride > 0, "dest format stride must be positive");
    assert(format.stride <= Vertex.sizeof, "dest format stride exceeds test buffer stride");

    foreach (i; 0 .. count) {
        size_t base = i * cast(size_t) format.stride;
        Vertex v = Vertex.init;

        if (format.position_matrix_index_offset >= 0) {
            v.position_matrix_index = read_s32(buffer, base + cast(size_t) format.position_matrix_index_offset);
        }

        if (format.position_offset >= 0) {
            foreach (j; 0 .. vat.position_count) {
                v.position[j] = read_f32(buffer, base + cast(size_t) format.position_offset + j * 4);
            }
            if (vat.position_count == 2) {
                v.position[2] = 0.0f;
            }
        }

        if (format.normal_offset >= 0) {
            if (vat.normal_count == 9) {
                foreach (j; 0 .. 3) {
                    v.normal[j] = read_f32(buffer, base + cast(size_t) format.normal_offset + j * 4);
                    v.binormal_t[j] = read_f32(buffer, base + cast(size_t) format.normal_offset + (j + 3) * 4);
                    v.binormal_b[j] = read_f32(buffer, base + cast(size_t) format.normal_offset + (j + 6) * 4);
                }
            } else {
                foreach (j; 0 .. 3) {
                    v.normal[j] = read_f32(buffer, base + cast(size_t) format.normal_offset + j * 4);
                }
            }
        }

        foreach (c; 0 .. 2) {
            if (format.color_offset[c] < 0) {
                continue;
            }
            int components = vat.color_count[c] == 3 ? 3 : 4;
            foreach (j; 0 .. components) {
                v.color[c][j] = read_f32(buffer, base + cast(size_t) format.color_offset[c] + j * 4);
            }
        }

        foreach (t; 0 .. 8) {
            if (format.texcoord_offset[t] < 0) {
                continue;
            }
            foreach (j; 0 .. vat.texcoord_count[t]) {
                v.texcoord[t][j] = read_f32(buffer, base + cast(size_t) format.texcoord_offset[t] + j * 4);
            }
        }

        vertices[i] = v;
    }

    return vertices;
}

void assert_vertex_matches(Vertex actual,
                           Vertex expected,
                           VertexDescriptor* vcd,
                           VertexAttributeTable* vat,
                           size_t vertex_index) {
    bool failed = false;
    bool[3] position_diff;
    bool[3] normal_diff;
    bool[3] binormal_t_diff;
    bool[3] binormal_b_diff;
    bool[4][2] color_diff;
    bool[2][8] texcoord_diff;
    bool position_matrix_index_diff = false;

    if (vcd.position_location != VertexAttributeLocation.NotPresent) {
        int count = vat.position_count == 2 ? 2 : 3;
        foreach (i; 0 .. count) {
            position_diff[i] = !close_enough(actual.position[i], expected.position[i]);
            failed = failed || position_diff[i];
        }
        if (vat.position_count == 2) {
            position_diff[2] = !close_enough(actual.position[2], expected.position[2]);
            failed = failed || position_diff[2];
        }
    }

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        position_matrix_index_diff = actual.position_matrix_index != expected.position_matrix_index;
        failed = failed || position_matrix_index_diff;
    }

    if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
        foreach (i; 0 .. 3) {
            normal_diff[i] = !close_enough(actual.normal[i], expected.normal[i]);
            failed = failed || normal_diff[i];
        }
        if (vat.normal_count == 9) {
            foreach (i; 0 .. 3) {
                binormal_t_diff[i] = !close_enough(actual.binormal_t[i], expected.binormal_t[i]);
                binormal_b_diff[i] = !close_enough(actual.binormal_b[i], expected.binormal_b[i]);
                failed = failed || binormal_t_diff[i] || binormal_b_diff[i];
            }
        }
    }

    foreach (c; 0 .. 2) {
        if (vcd.color_location[c] != VertexAttributeLocation.NotPresent) {
            int components = vat.color_count[c] == 3 ? 3 : 4;
            foreach (i; 0 .. components) {
                color_diff[c][i] = !close_enough(actual.color[c][i], expected.color[c][i]);
                failed = failed || color_diff[c][i];
            }
        }
    }

    foreach (t; 0 .. 8) {
        if (vcd.texcoord_location[t] != VertexAttributeLocation.NotPresent) {
            int components = vat.texcoord_count[t] == 1 ? 1 : 2;
            foreach (i; 0 .. components) {
                texcoord_diff[t][i] = !close_enough(actual.texcoord[t][i], expected.texcoord[t][i]);
                failed = failed || texcoord_diff[t][i];
            }
        }
    }

    if (!failed) {
        return;
    }

    cwritefln("<lred>Vertex %d mismatch</lred>", vertex_index);

    if (vcd.position_location != VertexAttributeLocation.NotPresent) {
        print_vec("position", actual.position[], expected.position[], position_diff[], 3);
    }

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        print_int("position_matrix_index",
            actual.position_matrix_index,
            expected.position_matrix_index,
            position_matrix_index_diff);
    }

    if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
        print_vec("normal", actual.normal[], expected.normal[], normal_diff[], 3);
        if (vat.normal_count == 9) {
            print_vec("binormal_t", actual.binormal_t[], expected.binormal_t[], binormal_t_diff[], 3);
            print_vec("binormal_b", actual.binormal_b[], expected.binormal_b[], binormal_b_diff[], 3);
        }
    }

    foreach (c; 0 .. 2) {
        if (vcd.color_location[c] != VertexAttributeLocation.NotPresent) {
            int components = vat.color_count[c] == 3 ? 3 : 4;
            print_vec(
                format("color[%d]", c),
                actual.color[c][],
                expected.color[c][],
                color_diff[c][],
                components);
        }
    }

    foreach (t; 0 .. 8) {
        if (vcd.texcoord_location[t] != VertexAttributeLocation.NotPresent) {
            int components = vat.texcoord_count[t] == 1 ? 1 : 2;
            print_vec(
                format("texcoord[%d]", t),
                actual.texcoord[t][],
                expected.texcoord[t][],
                texcoord_diff[t][],
                components);
        }
    }

    assert(false);
}

void assert_vertices_match(Vertex[] actual,
                           Vertex[] expected,
                           ref VertexFormat state) {
    assert(actual.length == expected.length, "vertex count mismatch");
    auto vcd = &state.vertex_descriptors[state.current_vat];
    auto vat = &state.vats[state.current_vat];
    foreach (i; 0 .. actual.length) {
        assert_vertex_matches(actual[i], expected[i], vcd, vat, i);
    }
}

/// Fluent builder for expected vertices to keep tests terse.
struct VertexBuilder {
    Vertex v;

    ref VertexBuilder position(float x, float y, float z = 0) {
        v.position = [x, y, z];
        return this;
    }

    ref VertexBuilder normal(float x, float y, float z) {
        v.normal = [x, y, z];
        return this;
    }

    ref VertexBuilder binormal_t(float x, float y, float z) {
        v.binormal_t = [x, y, z];
        return this;
    }

    ref VertexBuilder binormal_b(float x, float y, float z) {
        v.binormal_b = [x, y, z];
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

mixin template vertex_decoder_tests(alias VertexDecoder) {
@("vertex_decoder direct_position_dequantizes_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

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

@("vertex_decoder indexed_positions_u8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

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

@("vertex_decoder color_direct_passthrough")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGBA8888, 4);
    harness.set_color_global(0, [0.1f, 0.2f, 0.3f, 0.4f]);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u32_be(0xAABBCCDD)
                .finish(),
            1),
        [
            vertex().color(0,
                0xAA / 255.0f,
                0xBB / 255.0f,
                0xCC / 255.0f,
                0xDD / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder indexed_color_rgba8888")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Indexed8Bit, ColorFormat.RGBA8888, 4);
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

@("vertex_decoder texcoord_direct_shifted_s16")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

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

@("vertex_decoder position_matrix_index_present_and_absent")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position_matrix(VertexAttributeLocation.Direct);
    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.U8, 3, 0);

    auto stream_with_index = StreamBuilder()
        .stream_add_u8(0x05) // matrix index
        .stream_add_u8(0x0A) // position data X
        .stream_add_u8(0x00) // position data Y
        .stream_add_u8(0x00) // position data Z
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

@("vertex_decoder direct_position_s16_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.S16, 3, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_s16_be(8)
                .stream_add_s16_be(-8)
                .stream_add_s16_be(4)
                .finish(),
            1),
        [
            vertex().position(1.0f, -1.0f, 0.5f).build(),
        ],
        harness.state);
}

@("vertex_decoder direct_position_u8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.U8, 3, 0);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(10)
                .stream_add_u8(20)
                .stream_add_u8(30)
                .finish(),
            1),
        [
            vertex().position(10.0f, 20.0f, 30.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder direct_position_u16")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.U16, 3, 0);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0010)
                .stream_add_u16_be(0x0020)
                .stream_add_u16_be(0x0030)
                .finish(),
            1),
        [
            vertex().position(16.0f, 32.0f, 48.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder direct_position_s8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.S8, 3, 0);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0xFE) // -2
                .stream_add_u8(0x01)
                .stream_add_u8(0x7E) // 126
                .finish(),
            1),
        [
            vertex().position(-2.0f, 1.0f, 126.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder direct_position_s16")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.S16, 3, 0);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_s16_be(-1)
                .stream_add_s16_be(256)
                .stream_add_s16_be(-32768)
                .finish(),
            1),
        [
            vertex().position(-1.0f, 256.0f, -32768.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder direct_position_two_component_zero_fill")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.S16, 2, 0);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_s16_be(1)
                .stream_add_s16_be(2)
                .finish(),
            1),
        [
            vertex().position(1.0f, 2.0f, 0.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder normal_direct_s8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_normal(VertexAttributeLocation.Direct, NormalFormat.S8, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x40)
                .stream_add_u8(0xC0)
                .stream_add_u8(0x20)
                .finish(),
            1),
        [
            vertex().normal(1.0f, -1.0f, 0.5f).build(),
        ],
        harness.state);
}

@("vertex_decoder normal_direct_s16_nine_components")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_normal(VertexAttributeLocation.Direct, NormalFormat.S16, 9);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_s16_be(8192)
                .stream_add_s16_be(-8192)
                .stream_add_s16_be(4096)
                .stream_add_s16_be(16384)
                .stream_add_s16_be(0)
                .stream_add_s16_be(-16384)
                .stream_add_s16_be(8192)
                .stream_add_s16_be(0)
                .stream_add_s16_be(-8192)
                .finish(),
            1),
        [
            vertex()
                .normal(0.5f, -0.5f, 0.25f)
                .binormal_t(1.0f, 0.0f, -1.0f)
                .binormal_b(0.5f, 0.0f, -0.5f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder normal_indexed8_s8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_normal(VertexAttributeLocation.Indexed8Bit, NormalFormat.S8, 3);
    harness.write_array_bytes(1, 0x1200, [0x40, 0x00, 0x00, 0xC0, 0x00, 0x00], 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00)
                .stream_add_u8(0x01)
                .finish(),
            2),
        [
            vertex().normal(1.0f, 0.0f, 0.0f).build(),
            vertex().normal(-1.0f, 0.0f, 0.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_direct_f32_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.F32, 2, 1);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_float(2.0f)
                .stream_add_float(-2.0f)
                .finish(),
            1),
        [
            vertex().texcoord(0, 1.0f, -1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder position_and_texcoord_direct_f32_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.F32, 3, 1);
    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.F32, 2, 2);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_float(2.0f)   // position.x -> 1.0
                .stream_add_float(-4.0f)  // position.y -> -2.0
                .stream_add_float(0.5f)   // position.z -> 0.25
                .stream_add_float(2.0f)   // texcoord.s -> 0.5
                .stream_add_float(-2.0f)  // texcoord.t -> -0.5
                .finish(),
            1),
        [
            vertex()
                .position(1.0f, -2.0f, 0.25f)
                .texcoord(0, 0.5f, -0.5f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_direct_one_component_u8")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.U8, 1, 1);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(4)
                .finish(),
            1),
        [
            vertex().texcoord(0, 2.0f, 0.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_indexed8_s8_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Indexed8Bit, CoordFormat.S8, 2, 2);
    harness.write_array_bytes(4, 0x1300, [0xFC, 0x04], 2);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00)
                .finish(),
            1),
        [
            vertex().texcoord(0, -1.0f, 1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_matrix_index_skips_bytes")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.state.vertex_descriptors[harness.state.current_vat].texcoord_matrix_location[0] = VertexAttributeLocation.Direct;
    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.F32, 2, 0);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x07)
                .stream_add_float(1.0f)
                .stream_add_float(2.0f)
                .finish(),
            1),
        [
            vertex().texcoord(0, 1.0f, 2.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgb565")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGB565, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0xFFFF)
                .finish(),
            1),
        [
            vertex().color(0,
                248.0f / 255.0f,
                252.0f / 255.0f,
                248.0f / 255.0f,
                1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgb888")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGB888, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x10)
                .stream_add_u8(0x20)
                .stream_add_u8(0x30)
                .finish(),
            1),
        [
            vertex().color(0,
                48.0f / 255.0f,
                32.0f / 255.0f,
                16.0f / 255.0f,
                1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgb888x")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGB888x, 4);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x11)
                .stream_add_u8(0x22)
                .stream_add_u8(0x33)
                .stream_add_u8(0x44)
                .finish(),
            1),
        [
            vertex().color(0,
                68.0f / 255.0f,
                51.0f / 255.0f,
                34.0f / 255.0f,
                1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgba4444")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGBA4444, 4);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0xFFFF)
                .finish(),
            1),
        [
            vertex().color(0,
                240.0f / 255.0f,
                240.0f / 255.0f,
                240.0f / 255.0f,
                240.0f / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgba6666")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGBA6666, 4);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0xFF)
                .stream_add_u8(0xFF)
                .stream_add_u8(0xFF)
                .finish(),
            1),
        [
            vertex().color(0,
                252.0f / 255.0f,
                252.0f / 255.0f,
                252.0f / 255.0f,
                252.0f / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgba8888")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGBA8888, 4);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u32_be(0x01020304)
                .finish(),
            1),
        [
            vertex().color(0,
                1.0f / 255.0f,
                2.0f / 255.0f,
                3.0f / 255.0f,
                4.0f / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_indexed_rgb565")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Indexed8Bit, ColorFormat.RGB565, 3);
    harness.write_array_bytes(2, 0x1400, [0xFF, 0xFF], 2);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00)
                .finish(),
            1),
        [
            vertex().color(0,
                248.0f / 255.0f,
                252.0f / 255.0f,
                248.0f / 255.0f,
                1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder respects_max_vertices")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.U8, 3, 0);

    auto stream = StreamBuilder()
        .stream_add_u8(1)
        .stream_add_u8(2)
        .stream_add_u8(3)
        .stream_add_u8(4)
        .stream_add_u8(5)
        .stream_add_u8(6)
        .finish();

    auto decoded = harness.decode_with_max(decoder, stream, 2, 1);
    assert_vertices_match(
        decoded,
        [
            vertex().position(1.0f, 2.0f, 3.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder position_indexed16_u16_stride")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Indexed16Bit, CoordFormat.U16, 3, 0);
    harness.write_array_bytes(0, 0x1500,
        [
            0x00, 0x10, 0x00, 0x20, 0x00, 0x30, 0xAA, 0xAA,
            0x00, 0x40, 0x00, 0x50, 0x00, 0x60, 0xBB, 0xBB
        ],
        8);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0000)
                .stream_add_u16_be(0x0001)
                .finish(),
            2),
        [
            vertex().position(16.0f, 32.0f, 48.0f).build(),
            vertex().position(64.0f, 80.0f, 96.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder normal_indexed16_s16_stride")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_normal(VertexAttributeLocation.Indexed16Bit, NormalFormat.S16, 3);
    harness.write_array_bytes(1, 0x1600,
        [
            0x20, 0x00, 0xE0, 0x00, 0x10, 0x00, 0x11, 0x11,
            0x40, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x22, 0x22
        ],
        8);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0000)
                .stream_add_u16_be(0x0001)
                .finish(),
            2),
        [
            vertex().normal(0.5f, -0.5f, 0.25f).build(),
            vertex().normal(1.0f, -1.0f, 0.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder normal_indexed8_s16_nine_components")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_normal(VertexAttributeLocation.Indexed8Bit, NormalFormat.S16, 9);
    harness.write_array_bytes(1, 0x1650,
        [
            0x20, 0x00, 0xE0, 0x00, 0x10, 0x00, // normal
            0x40, 0x00, 0x00, 0x00, 0xC0, 0x00, // binormal T
            0x20, 0x00, 0x00, 0x00, 0xE0, 0x00  // binormal B
        ],
        18);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00)
                .finish(),
            1),
        [
            vertex()
                .normal(0.5f, -0.5f, 0.25f)
                .binormal_t(1.0f, 0.0f, -1.0f)
                .binormal_b(0.5f, 0.0f, -0.5f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_indexed16_u16_shift_stride")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Indexed16Bit, CoordFormat.U16, 2, 2);
    harness.write_array_bytes(4, 0x1700,
        [
            0x00, 0x08, 0x00, 0x04, 0xEE, 0xEE,
            0x00, 0x10, 0x00, 0x20, 0xFF, 0xFF
        ],
        6);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0000)
                .stream_add_u16_be(0x0001)
                .finish(),
            2),
        [
            vertex().texcoord(0, 2.0f, 1.0f).build(),
            vertex().texcoord(0, 4.0f, 8.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_indexed16_rgba8888_stride")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Indexed16Bit, ColorFormat.RGBA8888, 4);
    harness.write_array_bytes(2, 0x1800,
        [
            0x01, 0x02, 0x03, 0x04, 0xAA, 0xAA,
            0x10, 0x20, 0x30, 0x40, 0xBB, 0xBB
        ],
        6);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0000)
                .stream_add_u16_be(0x0001)
                .finish(),
            2),
        [
            vertex().color(0,
                1.0f / 255.0f,
                2.0f / 255.0f,
                3.0f / 255.0f,
                4.0f / 255.0f).build(),
            vertex().color(0,
                16.0f / 255.0f,
                32.0f / 255.0f,
                48.0f / 255.0f,
                64.0f / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder mixed_direct_and_indexed")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.S8, 3, 1);
    harness.set_normal(VertexAttributeLocation.Indexed8Bit, NormalFormat.S8, 3);
    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGBA8888, 4);

    harness.write_array_bytes(1, 0x1900, [0x40, 0x40, 0x40], 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x02)
                .stream_add_u8(0xFE)
                .stream_add_u8(0x04)
                .stream_add_u8(0x00) // normal index
                .stream_add_u32_be(0x0A0B0C0D)
                .finish(),
            1),
        [
            vertex()
                .position(1.0f, -1.0f, 2.0f)
                .normal(1.0f, 1.0f, 1.0f)
                .color(0,
                    10.0f / 255.0f,
                    11.0f / 255.0f,
                    12.0f / 255.0f,
                    13.0f / 255.0f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder multiple_texcoords_direct")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.U8, 2, 0);
    harness.set_texcoord(1, VertexAttributeLocation.Direct, CoordFormat.S16, 2, 1);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(1)
                .stream_add_u8(2)
                .stream_add_s16_be(4)
                .stream_add_s16_be(-4)
                .finish(),
            1),
        [
            vertex()
                .texcoord(0, 1.0f, 2.0f)
                .texcoord(1, 2.0f, -2.0f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder short_stream_stops_early")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.U8, 3, 0);

    auto stream = StreamBuilder()
        .stream_add_u8(1)
        .stream_add_u8(2)
        .stream_add_u8(3)
        .finish();

    auto decoded = harness.decode_with_max(decoder, stream, 2, 2);
    assert_vertices_match(
        decoded,
        [
            vertex().position(1.0f, 2.0f, 3.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder vat1_mixed_attrs")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.state.current_vat = 1;
    auto vcd = &harness.state.vertex_descriptors[1];
    auto vat = &harness.state.vats[1];
    vcd.position_location = VertexAttributeLocation.Direct;
    vcd.normal_location = VertexAttributeLocation.Direct;
    vcd.color_location[0] = VertexAttributeLocation.Direct;
    vcd.texcoord_location[0] = VertexAttributeLocation.Direct;
    vat.position_format = CoordFormat.S16;
    vat.position_count = 3;
    vat.position_shift = 1;
    vat.normal_format = NormalFormat.S8;
    vat.normal_count = 3;
    vat.color_format[0] = ColorFormat.RGBA8888;
    vat.color_count[0] = 4;
    vat.texcoord_format[0] = CoordFormat.U8;
    vat.texcoord_count[0] = 2;
    vat.texcoord_shift[0] = 0;

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_s16_be(4)
                .stream_add_s16_be(-4)
                .stream_add_s16_be(2)
                .stream_add_u8(0x40)
                .stream_add_u8(0xC0)
                .stream_add_u8(0x20)
                .stream_add_u32_be(0x0A0B0C0D)
                .stream_add_u8(5)
                .stream_add_u8(6)
                .finish(),
            1),
        [
            vertex()
                .position(2.0f, -2.0f, 1.0f)
                .normal(1.0f, -1.0f, 0.5f)
                .color(0,
                    10.0f / 255.0f,
                    11.0f / 255.0f,
                    12.0f / 255.0f,
                    13.0f / 255.0f)
                .texcoord(0, 5.0f, 6.0f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder normal_direct_f32")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_normal(VertexAttributeLocation.Direct, NormalFormat.F32, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_float(0.25f)
                .stream_add_float(-0.5f)
                .stream_add_float(1.0f)
                .finish(),
            1),
        [
            vertex().normal(0.25f, -0.5f, 1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder position_direct_f32_shifted")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Direct, CoordFormat.F32, 3, 2);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_float(8.0f)
                .stream_add_float(-4.0f)
                .stream_add_float(2.0f)
                .finish(),
            1),
        [
            vertex().position(2.0f, -1.0f, 0.5f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_direct_rgb888_defaults_alpha")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Direct, ColorFormat.RGB888, 3);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0xAA)
                .stream_add_u8(0xBB)
                .stream_add_u8(0xCC)
                .finish(),
            1),
        [
            vertex().color(0,
                204.0f / 255.0f,
                187.0f / 255.0f,
                170.0f / 255.0f,
                1.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder color_indexed16_rgba4444_stride")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_color(0, VertexAttributeLocation.Indexed16Bit, ColorFormat.RGBA4444, 4);
    harness.write_array_bytes(2, 0x1A00,
        [
            0x12, 0x34, 0x55, 0x55,
            0xFE, 0xDC, 0x66, 0x66
        ],
        4);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0000)
                .stream_add_u16_be(0x0001)
                .finish(),
            2),
        [
            vertex().color(0,
                (0x4 << 4) / 255.0f,
                (0x3 << 4) / 255.0f,
                (0x2 << 4) / 255.0f,
                (0x1 << 4) / 255.0f).build(),
            vertex().color(0,
                (0xC << 4) / 255.0f,
                (0xD << 4) / 255.0f,
                (0xE << 4) / 255.0f,
                (0xF << 4) / 255.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_direct_u16_single_component_shift")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Direct, CoordFormat.U16, 1, 1);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u16_be(0x0004)
                .finish(),
            1),
        [
            vertex().texcoord(0, 2.0f, 0.0f).build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_indexed8_two_slots")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_texcoord(0, VertexAttributeLocation.Indexed8Bit, CoordFormat.U8, 2, 0);
    harness.set_texcoord(1, VertexAttributeLocation.Indexed8Bit, CoordFormat.S8, 2, 1);
    harness.write_array_bytes(4, 0x1B00, [1, 2, 3, 4], 2);
    harness.write_array_bytes(5, 0x1C00, [0x02, 0xFE, 0x04, 0xFC], 2);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00)
                .stream_add_u8(0x00)
                .finish(),
            1),
        [
            vertex()
                .texcoord(0, 1.0f, 2.0f)
                .texcoord(1, 1.0f, -1.0f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder multi_vertex_stride_mix")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    harness.set_position(VertexAttributeLocation.Indexed8Bit, CoordFormat.U8, 3, 0);
    harness.set_color(0, VertexAttributeLocation.Indexed8Bit, ColorFormat.RGBA8888, 4);
    harness.write_array_bytes(0, 0x1D00,
        [
            1, 2, 3, 99, 99,
            4, 5, 6, 88, 88
        ],
        5);
    harness.write_array_bytes(2, 0x1E00,
        [
            0x11, 0x22, 0x33, 0x44, 0xAA, 0xAA,
            0xAA, 0xBB, 0xCC, 0xDD, 0xBB, 0xBB
        ],
        6);

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(0x00) // pos idx 0
                .stream_add_u8(0x00) // color idx 0
                .stream_add_u8(0x01) // pos idx 1
                .stream_add_u8(0x01) // color idx 1
                .finish(),
            2),
        [
            vertex()
                .position(1.0f, 2.0f, 3.0f)
                .color(0,
                    0x11 / 255.0f,
                    0x22 / 255.0f,
                    0x33 / 255.0f,
                    0x44 / 255.0f)
                .build(),
            vertex()
                .position(4.0f, 5.0f, 6.0f)
                .color(0,
                    0xAA / 255.0f,
                    0xBB / 255.0f,
                    0xCC / 255.0f,
                    0xDD / 255.0f)
                .build(),
        ],
        harness.state);
}

@("vertex_decoder texcoord_count_bit_sets_two_components")
unittest {
    auto harness = VertexDecodeHarness.make();
    auto decoder = new VertexDecoder();

    auto vat = &harness.state.vats[harness.state.current_vat];
    auto vcd = &harness.state.vertex_descriptors[harness.state.current_vat];
    vcd.texcoord_location[0] = VertexAttributeLocation.Direct;
    vat.texcoord_count[0] = 2;
    vat.texcoord_format[0] = CoordFormat.U8;
    vat.texcoord_shift[0] = 0;

    assert_vertices_match(
        harness.decode(decoder,
            StreamBuilder()
                .stream_add_u8(9)
                .stream_add_u8(8)
                .finish(),
            1),
        [
            vertex().texcoord(0, 9.0f, 8.0f).build(),
        ],
        harness.state);
}
}

mixin vertex_decoder_tests!(VertexInterpreterDecoder);
mixin vertex_decoder_tests!(VertexJitDecoder);
