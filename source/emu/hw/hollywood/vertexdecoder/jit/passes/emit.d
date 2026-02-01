module emu.hw.hollywood.vertexdecoder.jit.passes.emit;

import core.bitop;
import core.stdc.string;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.jit.code;
import emu.hw.hollywood.vertexdecoder.jit.passes.ir;
import emu.hw.hollywood.vertexdecoder.types;
import gallinule.x86;
import util.bitop;
import util.force_cast;
import util.log;
import util.number;

struct Range {
    u8 offset;
    u8 length;

    bool overlaps(Range other) {
        return !(offset + length <= other.offset || other.offset + other.length <= offset);
    }

    bool contains(Range other) {
        return offset <= other.offset && (offset + length) >= (other.offset + other.length);
    }

    void shift_right(u8 amount) {
        offset += amount;
    }
}

enum LocationType : u8 {
    SourceBuffer,
    Ymm,
}

struct SourceBufferLocation {
    Range range;
}

struct YmmLocation {
    u8    index;
    Range range;
}

struct Location {
    LocationType kind;

    union {
        SourceBufferLocation source_buffer;
        YmmLocation          ymm;
    }
}

enum AttributeStatus : u8 {
    Unused,
    AwaitingAlignment,
    AwaitingFloatExpansion,
    AwaitingDequantization,
    AwaitingStore,
    AwaitingIndexedInsert,
    Stored
}

enum CMPGT_OQ = 0x1e;

struct AttributeDecodeState {
    AttributeStatus status;
    Location        location;
    u8              element_size;
    u8              num_output_dwords;
}

struct VertexDecodeState {
    AttributeDecodeState    position_matrix;
    AttributeDecodeState[8] texcoord_matrix;
    AttributeDecodeState    position;
    AttributeDecodeState    normal;
    AttributeDecodeState    binormal_t;
    AttributeDecodeState    binormal_b;
    AttributeDecodeState[2] color;
    AttributeDecodeState[8] texcoord;

    size_t source_stream_size;

    // Tracking for YMM allocation and alignment passes.
    YMM[]      allocated_ymms;

    private static YMM make_ymm(ubyte index) {
        return YMM(index, index >= 8);
    }

    YMM new_ymm() {
        auto ymm = make_ymm(cast(ubyte) allocated_ymms.length);
        allocated_ymms ~= ymm;
        return ymm;
    }

    YMM tmp_ymm() {
        // Reserve the last YMM as a temporary scratch register.
        return make_ymm(15);
    }

    YMM tmp_ymm2() {
        return make_ymm(13);
    }

    void foreach_attribute(scope void delegate(ref AttributeDecodeState) callback) {
        callback(position_matrix);

        foreach (ref tm; texcoord_matrix) {
            callback(tm);
        }

        callback(position);
        callback(normal);
        callback(binormal_t);
        callback(binormal_b);

        foreach (ref c; color) {
            callback(c);
        }

        foreach (ref t; texcoord) {
            callback(t);
        }
    }

    int opApply(scope int delegate(ref AttributeDecodeState) dg) {
        int result;

        auto applyOne = (ref AttributeDecodeState ads) {
            if (result != 0) return;
            result = dg(ads);
        };

        applyOne(position_matrix);

        foreach (ref tm; texcoord_matrix) {
            applyOne(tm);
        }

        applyOne(position);
        applyOne(normal);

        foreach (ref c; color) {
            applyOne(c);
        }

        foreach (ref t; texcoord) {
            applyOne(t);
        }

        return result;
    }
}

private u8 coord_size(CoordFormat fmt) {
    final switch (fmt) {
        case CoordFormat.U8:
        case CoordFormat.S8:  return 1;
        case CoordFormat.U16:
        case CoordFormat.S16: return 2;
        case CoordFormat.F32: return 4;
    }
}

private u8 normal_size(NormalFormat fmt) {
    final switch (fmt) {
        case NormalFormat.S8:  return 1;
        case NormalFormat.S16: return 2;
        case NormalFormat.F32: return 4;
    }
}

private u8 color_size(ColorFormat fmt) {
    final switch (fmt) {
        case ColorFormat.RGB565:   return 2;
        case ColorFormat.RGB888:   return 3;
        case ColorFormat.RGB888x:  return 4;
        case ColorFormat.RGBA4444: return 2;
        case ColorFormat.RGBA6666: return 3;
        case ColorFormat.RGBA8888: return 4;
    }
}

private bool is_rgb8_color(ColorFormat fmt) {
    return fmt == ColorFormat.RGB888 || fmt == ColorFormat.RGB888x || fmt == ColorFormat.RGBA8888;
}

private u64 make_mask(u64 offset, u64 len) {
    assert_hollywood(offset + len <= 64, "vertex exceeds 64 bytes");
    if (len == 0) return 0;
    u64 m = (len == 64) ? ~cast(u64) 0 : ((1UL << len) - 1);
    return m << offset;
}

private u64 mask_from_range(Range range) {
    return make_mask(range.offset, range.length);
}

private Size size_from_bytes(u8 bytes) {
    switch (bytes) {
        case 1: return Size.Size8;
        case 2: return Size.Size16;
        case 4: return Size.Size32;
        default: error_hollywood("unexpected element size");
    }
}

private int size_to_bytes(Size size) {
    switch (size) {
        case Size.Size8:  return 1;
        case Size.Size16: return 2;
        case Size.Size32: return 4;
        default: error_hollywood("unexpected size");
    }
}

private AttributeDecodeState make_source_state(AttributeStatus status, u32 offset, u32 length, u8 element_size, u8 num_output_dwords) {
    AttributeDecodeState ads;
    ads.status = status;
    ads.location.kind = LocationType.SourceBuffer;
    ads.location.source_buffer = SourceBufferLocation(Range(cast(u8) offset, cast(u8) length));
    ads.element_size = element_size;
    ads.num_output_dwords = num_output_dwords;
    return ads;
}

private void push_sext(ref Op[] ops, u64 mask, Size from, u8 ymm_index) {
    Op op;
    op.kind = OpKind.Sext;
    op.source_mask = mask;
    op.ymm_index = ymm_index;
    op.sext.from = from;
    ops ~= op;
}

private void push_zext(ref Op[] ops, u64 mask, Size from, u8 ymm_index) {
    Op op;
    op.kind = OpKind.Zext;
    op.source_mask = mask;
    op.ymm_index = ymm_index;
    op.zext.from = from;
    ops ~= op;
}

private void push_cvt(ref Op[] ops, u64 mask, u8 ymm_index) {
    Op op;
    op.kind = OpKind.CvtToFloat;
    op.source_mask = mask;
    op.ymm_index = ymm_index;
    ops ~= op;
}

private void push_mul(ref Op[] ops, u64 mask, float factor, u8 ymm_index) {
    Op op;
    op.kind = OpKind.Mul;
    op.source_mask = mask;
    op.ymm_index = ymm_index;
    op.mul.factor = factor;
    ops ~= op;
}

private void push_store(ref Op[] ops, u64 mask, u32 dest_offset, u8 ymm_index) {
    Op op;
    op.kind = OpKind.Store;
    op.source_mask = mask;
    op.ymm_index = ymm_index;
    op.store.dest_offset = dest_offset;
    ops ~= op;
}

private void push_color(ref Op[] ops, u64 mask, ColorFormat fmt, u32 dest_offset, u8 ymm_index) {
    Op op;
    op.kind = OpKind.DequantizeColor;
    op.source_mask = mask;
    op.ymm_index = ymm_index;
    op.dequantize_color.format = fmt;
    ops ~= op;

    push_store(ops, mask, dest_offset, ymm_index);
}

private bool is_indexed(VertexAttributeLocation loc) {
    return loc == VertexAttributeLocation.Indexed8Bit || loc == VertexAttributeLocation.Indexed16Bit;
}

private void push_indexed_coord(ref Op[] ops, ref AttributeDecodeState ads, u8 stream_offset,
                                 VertexAttributeLocation loc, u8 array_number,
                                 u8 component_count, float scale, CoordFormat fmt) {
    Op op;
    op.kind = OpKind.IndexedLoad;
    op.ymm_index = ads.location.ymm.index;
    op.indexed_load.stream_offset = stream_offset;
    op.indexed_load.index_size = (loc == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
    op.indexed_load.array_number = array_number;
    op.indexed_load.attr_kind = IndexedAttrKind.Coord;
    op.indexed_load.component_count = component_count;
    op.indexed_load.scale = scale;
    op.indexed_load.ymm_index = ads.location.ymm.index;
    op.indexed_load.ymm_byte_offset = ads.location.ymm.range.offset;
    op.indexed_load.coord_format = fmt;
    ops ~= op;
}

private void push_indexed_normal(ref Op[] ops, ref AttributeDecodeState ads, u8 stream_offset,
                                  VertexAttributeLocation loc, u8 array_number,
                                  u8 component_count, float scale, NormalFormat fmt,
                                  u8 first_component_index) {
    Op op;
    op.kind = OpKind.IndexedLoad;
    op.ymm_index = ads.location.ymm.index;
    op.indexed_load.stream_offset = stream_offset;
    op.indexed_load.index_size = (loc == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
    op.indexed_load.array_number = array_number;
    op.indexed_load.attr_kind = IndexedAttrKind.Normal;
    op.indexed_load.component_count = component_count;
    op.indexed_load.scale = scale;
    op.indexed_load.first_component_index = first_component_index;
    op.indexed_load.ymm_index = ads.location.ymm.index;
    op.indexed_load.ymm_byte_offset = ads.location.ymm.range.offset;
    op.indexed_load.normal_format = fmt;
    ops ~= op;
}

private void push_indexed_color(ref Op[] ops, ref AttributeDecodeState ads, u8 stream_offset,
                                 VertexAttributeLocation loc, u8 array_number,
                                 float scale, ColorFormat fmt) {
    Op op;
    op.kind = OpKind.IndexedLoad;
    op.ymm_index = ads.location.ymm.index;
    op.indexed_load.stream_offset = stream_offset;
    op.indexed_load.index_size = (loc == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
    op.indexed_load.array_number = array_number;
    op.indexed_load.attr_kind = IndexedAttrKind.Color;
    op.indexed_load.component_count = 1;
    op.indexed_load.scale = scale;
    op.indexed_load.ymm_index = ads.location.ymm.index;
    op.indexed_load.ymm_byte_offset = ads.location.ymm.range.offset;
    op.indexed_load.color_format = fmt;
    ops ~= op;
}

Op[] create_parallel_ops(VertexFormat state, VertexDecodeState* vds) {
    Op[] ops;

    auto vcd = &state.vertex_descriptors[state.current_vat];
    auto vat = &state.vats[state.current_vat];

    auto mask_from_ads = (ref AttributeDecodeState ads) {
        assert_hollywood(ads.location.kind == LocationType.Ymm,
            "expected YMM location after allocation");
        return mask_from_range(ads.location.ymm.range);
    };

    auto mask_from_ads_with_stride = (ref AttributeDecodeState ads, u8 element_size_bytes) {
        assert_hollywood(ads.location.kind == LocationType.Ymm,
            "expected YMM location after allocation");

        u64 mask = 0;
        u8 offset = ads.location.ymm.range.offset;
        for (u8 i = 0; i < ads.location.ymm.range.length; i += element_size_bytes) {
            mask |= make_mask(offset, element_size_bytes);
            offset += 4;
        }

        return mask;
    };

    // Recompute stream offsets for indexed attributes (original source_buffer.range.offset
    // was overwritten during YMM allocation).
    u8 stream_offset = 0;

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        stream_offset += 1;
    }

    for (int i = 0; i < 8; i++) {
        if (vcd.texcoord_matrix_location[i] != VertexAttributeLocation.NotPresent) {
            stream_offset += 1;
        }
    }

    // --- Position ---
    u8 position_stream_offset = stream_offset;
    if (vcd.position_location != VertexAttributeLocation.NotPresent) {
        if (vcd.position_location == VertexAttributeLocation.Direct) {
            stream_offset += cast(u8)(coord_size(vat.position_format) * vat.position_count);
        } else {
            stream_offset += is_indexed(vcd.position_location) ?
                ((vcd.position_location == VertexAttributeLocation.Indexed8Bit) ? 1 : 2) : 0;
        }
    }

    // --- Normal ---
    u8 normal_stream_offset = stream_offset;
    if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
        if (vcd.normal_location == VertexAttributeLocation.Direct) {
            stream_offset += cast(u8)(normal_size(vat.normal_format) * vat.normal_count);
        } else {
            stream_offset += (vcd.normal_location == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
        }
    }

    // --- Colors ---
    u8[2] color_stream_offsets;
    for (int c = 0; c < 2; c++) {
        color_stream_offsets[c] = stream_offset;
        if (vcd.color_location[c] == VertexAttributeLocation.NotPresent) continue;
        if (vcd.color_location[c] == VertexAttributeLocation.Direct) {
            stream_offset += color_size(vat.color_format[c]);
        } else {
            stream_offset += (vcd.color_location[c] == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
        }
    }

    // --- Texcoords ---
    u8[8] texcoord_stream_offsets;
    for (int t = 0; t < 8; t++) {
        texcoord_stream_offsets[t] = stream_offset;
        if (vcd.texcoord_location[t] == VertexAttributeLocation.NotPresent) continue;
        if (vcd.texcoord_location[t] == VertexAttributeLocation.Direct) {
            stream_offset += cast(u8)(coord_size(vat.texcoord_format[t]) * vat.texcoord_count[t]);
        } else {
            stream_offset += (vcd.texcoord_location[t] == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
        }
    }

    // --- Now generate ops ---

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        auto mask = mask_from_ads(vds.position_matrix);
        push_zext(ops, mask, Size.Size8, vds.position_matrix.location.ymm.index);
        push_store(ops, mask, Vertex.position_matrix_index.offsetof, vds.position_matrix.location.ymm.index);
    }

    if (vcd.position_location == VertexAttributeLocation.Direct) {
        u8 size_bytes = coord_size(vat.position_format);
        auto mask = mask_from_ads_with_stride(vds.position, size_bytes);

        if (vat.position_format != CoordFormat.F32) {
            if (vat.position_format == CoordFormat.S8 || vat.position_format == CoordFormat.S16) {
                push_sext(ops, mask, size_from_bytes(size_bytes), vds.position.location.ymm.index);
            } else {
                push_zext(ops, mask, size_from_bytes(size_bytes), vds.position.location.ymm.index);
            }
            push_cvt(ops, mask, vds.position.location.ymm.index);
        }

        if (vat.position_shift != 0) {
            push_mul(ops, mask, 1.0f / cast(float) (1u << vat.position_shift), vds.position.location.ymm.index);
        }

        push_store(ops, mask, Vertex.position.offsetof, vds.position.location.ymm.index);
    } else if (is_indexed(vcd.position_location)) {
        float scale = (vat.position_shift != 0) ? 1.0f / cast(float)(1u << vat.position_shift) : 1.0f;
        push_indexed_coord(ops, vds.position, position_stream_offset,
            vcd.position_location, 0, cast(u8) vat.position_count, scale, vat.position_format);
    }

    if (vcd.normal_location == VertexAttributeLocation.Direct) {
        u8 size_bytes = normal_size(vat.normal_format);

        float factor = 1.0f;
        final switch (vat.normal_format) {
            case NormalFormat.S8:  factor = 1.0f / 64.0f; break;
            case NormalFormat.S16: factor = 1.0f / 16384.0f; break;
            case NormalFormat.F32: factor = 1.0f; break;
        }

        void emit_direct_normal_ops(ref AttributeDecodeState ads, u32 dest_offset) {
            auto mask = mask_from_ads_with_stride(ads, size_bytes);
            if (vat.normal_format != NormalFormat.F32) {
                push_sext(ops, mask, size_from_bytes(size_bytes), ads.location.ymm.index);
                push_cvt(ops, mask, ads.location.ymm.index);
            }
            if (factor != 1.0f) {
                push_mul(ops, mask, factor, ads.location.ymm.index);
            }
            push_store(ops, mask, dest_offset, ads.location.ymm.index);
        }

        emit_direct_normal_ops(vds.normal, Vertex.normal.offsetof);
        if (vat.normal_count == 9) {
            emit_direct_normal_ops(vds.binormal_t, Vertex.binormal_t.offsetof);
            emit_direct_normal_ops(vds.binormal_b, Vertex.binormal_b.offsetof);
        }
    } else if (is_indexed(vcd.normal_location)) {
        float scale = 1.0f;
        final switch (vat.normal_format) {
            case NormalFormat.S8:  scale = 1.0f / 64.0f; break;
            case NormalFormat.S16: scale = 1.0f / 16384.0f; break;
            case NormalFormat.F32: scale = 1.0f; break;
        }
        push_indexed_normal(ops, vds.normal, normal_stream_offset,
            vcd.normal_location, 1, 3, scale, vat.normal_format, 0);
        if (vat.normal_count == 9) {
            push_indexed_normal(ops, vds.binormal_t, normal_stream_offset,
                vcd.normal_location, 1, 3, scale, vat.normal_format, 3);
            push_indexed_normal(ops, vds.binormal_b, normal_stream_offset,
                vcd.normal_location, 1, 3, scale, vat.normal_format, 6);
        }
    }

    for (int c = 0; c < 2; c++) {
        if (vcd.color_location[c] == VertexAttributeLocation.NotPresent) continue;

        if (vcd.color_location[c] == VertexAttributeLocation.Direct) {
            auto mask = mask_from_ads(vds.color[c]);
            u32 dest = cast(u32) (Vertex.color.offsetof + cast(size_t) (c * 16));
            push_color(ops, mask, vat.color_format[c], dest, vds.color[c].location.ymm.index);
        } else {
            push_indexed_color(ops, vds.color[c], color_stream_offsets[c],
                vcd.color_location[c], cast(u8)(c + 2), 1.0f, vat.color_format[c]);
        }
    }

    for (int t = 0; t < 8; t++) {
        if (vcd.texcoord_location[t] == VertexAttributeLocation.NotPresent) continue;

        if (vcd.texcoord_location[t] == VertexAttributeLocation.Direct) {
            u8 size_bytes = coord_size(vat.texcoord_format[t]);
            auto mask = mask_from_ads_with_stride(vds.texcoord[t], size_bytes);

            if (vat.texcoord_format[t] != CoordFormat.F32) {
                if (vat.texcoord_format[t] == CoordFormat.S8 || vat.texcoord_format[t] == CoordFormat.S16) {
                    push_sext(ops, mask, size_from_bytes(size_bytes), vds.texcoord[t].location.ymm.index);
                } else {
                    push_zext(ops, mask, size_from_bytes(size_bytes), vds.texcoord[t].location.ymm.index);
                }
                push_cvt(ops, mask, vds.texcoord[t].location.ymm.index);
            }

            if (vat.texcoord_shift[t] != 0) {
                push_mul(ops, mask, 1.0f / cast(float) (1u << vat.texcoord_shift[t]), vds.texcoord[t].location.ymm.index);
            }

            push_store(ops, mask, cast(u32) (Vertex.texcoord.offsetof + cast(size_t) (t * 8)), vds.texcoord[t].location.ymm.index);
        } else {
            float scale = (vat.texcoord_shift[t] != 0) ? 1.0f / cast(float)(1u << vat.texcoord_shift[t]) : 1.0f;
            push_indexed_coord(ops, vds.texcoord[t], texcoord_stream_offsets[t],
                vcd.texcoord_location[t], cast(u8)(t + 4), cast(u8) vat.texcoord_count[t], scale, vat.texcoord_format[t]);
        }
    }

    assert_hollywood(vds.source_stream_size <= 64, "vertex exceeds 64 bytes");
    return ops;
}

VertexDecodeState construct_vertex_decode_state(VertexFormat format) {
    VertexDecodeState vds;
    auto vcd = &format.vertex_descriptors[format.current_vat];
    auto vat = &format.vats[format.current_vat];

    u32 offset = 0;

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        vds.position_matrix = make_source_state(AttributeStatus.AwaitingAlignment, offset, 1, 1, 1);
        offset += 1;
    }

    for (int i = 0; i < 8; i++) {
        if (vcd.texcoord_matrix_location[i] != VertexAttributeLocation.NotPresent) {
            // Texcoord matrix indices are present in the stream but ignored by the decoder today.
            vds.texcoord_matrix[i] = make_source_state(AttributeStatus.Unused, offset, 1, 1, 1);
            offset += 1;
        }
    }

    if (vcd.position_location == VertexAttributeLocation.Direct) {
        u32 len = cast(u32) coord_size(vat.position_format) * cast(u32) vat.position_count;
        vds.position = make_source_state(AttributeStatus.AwaitingAlignment, offset, len, coord_size(vat.position_format), cast(u8) vat.position_count);
        offset += len;
    } else if (vcd.position_location == VertexAttributeLocation.Indexed8Bit
            || vcd.position_location == VertexAttributeLocation.Indexed16Bit) {
        u8 index_size = (vcd.position_location == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
        u32 output_len = cast(u32) coord_size(vat.position_format) * cast(u32) vat.position_count;
        vds.position = make_source_state(AttributeStatus.AwaitingIndexedInsert, offset, output_len, index_size, cast(u8) vat.position_count);
        offset += index_size;
    }

    if (vcd.normal_location == VertexAttributeLocation.Direct) {
        u8 elem = normal_size(vat.normal_format);
        u32 len_per_vector = cast(u32) elem * 3;
        vds.normal = make_source_state(AttributeStatus.AwaitingAlignment, offset, len_per_vector, elem, 3);
        offset += len_per_vector;
        if (vat.normal_count == 9) {
            vds.binormal_t = make_source_state(AttributeStatus.AwaitingAlignment, offset, len_per_vector, elem, 3);
            offset += len_per_vector;
            vds.binormal_b = make_source_state(AttributeStatus.AwaitingAlignment, offset, len_per_vector, elem, 3);
            offset += len_per_vector;
        }
    } else if (vcd.normal_location == VertexAttributeLocation.Indexed8Bit
            || vcd.normal_location == VertexAttributeLocation.Indexed16Bit) {
        u8 index_size = (vcd.normal_location == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
        u8 elem = normal_size(vat.normal_format);
        u32 output_len = cast(u32) elem * 3;
        vds.normal = make_source_state(AttributeStatus.AwaitingIndexedInsert, offset, output_len, index_size, 3);
        if (vat.normal_count == 9) {
            vds.binormal_t = make_source_state(AttributeStatus.AwaitingIndexedInsert, offset, output_len, index_size, 3);
            vds.binormal_b = make_source_state(AttributeStatus.AwaitingIndexedInsert, offset, output_len, index_size, 3);
        }
        offset += index_size;
    }

    for (int c = 0; c < 2; c++) {
        if (vcd.color_location[c] == VertexAttributeLocation.NotPresent) continue;

        if (vcd.color_location[c] == VertexAttributeLocation.Direct) {
            u32 len = color_size(vat.color_format[c]);
            vds.color[c] = make_source_state(AttributeStatus.AwaitingAlignment, offset, len, color_size(vat.color_format[c]), 1);
            offset += len;
        } else {
            u8 index_size = (vcd.color_location[c] == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
            u32 output_len = color_size(vat.color_format[c]);
            vds.color[c] = make_source_state(AttributeStatus.AwaitingIndexedInsert, offset, output_len, index_size, 1);
            offset += index_size;
        }
    }

    for (int t = 0; t < 8; t++) {
        if (vcd.texcoord_location[t] == VertexAttributeLocation.NotPresent) continue;

        if (vcd.texcoord_location[t] == VertexAttributeLocation.Direct) {
            u32 len = cast(u32) coord_size(vat.texcoord_format[t]) * cast(u32) vat.texcoord_count[t];
            vds.texcoord[t] = make_source_state(AttributeStatus.AwaitingAlignment, offset, len, coord_size(vat.texcoord_format[t]), cast(u8) vat.texcoord_count[t]);
            offset += len;
        } else {
            u8 index_size = (vcd.texcoord_location[t] == VertexAttributeLocation.Indexed8Bit) ? 1 : 2;
            u32 output_len = cast(u32) coord_size(vat.texcoord_format[t]) * cast(u32) vat.texcoord_count[t];
            vds.texcoord[t] = make_source_state(AttributeStatus.AwaitingIndexedInsert, offset, output_len, index_size, cast(u8) vat.texcoord_count[t]);
            offset += index_size;
        }
    }

    vds.source_stream_size = offset;

    return vds;
}

void allocate_ymms_for_attributes_unaligned(Code code, VertexDecodeState* vds) {
    int attributes_collected_for_current_ymm = 0;
    int current_offset_within_source_stream  = 0;
    int offset_for_ymm_load                  = 0;

    AttributeDecodeState*[8] attributes_in_current_ymm;

    auto mark_and_load_attributes = () {
        auto ymm = vds.new_ymm();
        code.vmovups(ymm, code.ymmwordPtr(rdi, offset_for_ymm_load));

        for (int i = 0; i < attributes_collected_for_current_ymm; i++) {
            auto ads = attributes_in_current_ymm[i];

            // Compute where this attribute's source data lives within the loaded
            // YMM by subtracting the load base from the absolute source offset.
            int ymm_offset = ads.location.source_buffer.range.offset - offset_for_ymm_load;

            ads.location.kind = LocationType.Ymm;
            ads.location.ymm.range.length = cast(u8) ads.location.source_buffer.range.length;
            ads.location.ymm.range.offset = cast(u8) ymm_offset;
            ads.location.ymm.index = ymm.index;
        }

        attributes_collected_for_current_ymm = 0;
        current_offset_within_source_stream  = 0;
        offset_for_ymm_load                  = 0;
    };

    int float_expanded_bytes = 0;

    // Compute the vmovups load offset for the current batch of attributes.
    //
    // By default, we load from the first attribute's source position so that
    // source data starts at YMM byte 0. This avoids the case where source
    // bytes land past the 128-bit lane boundary (byte 16) and become
    // inaccessible to vpshufb in the lower lane.
    //
    // When float-expanded output exceeds 16 bytes (one XMM lane), we also
    // need source data in BOTH halves of the YMM. In that case, we shift
    // the load backwards so that source bytes producing the first 16 output
    // bytes land in the lower half, and the rest land in the upper half.
    auto compute_ymm_load_offset = () {
        int first_source_offset = attributes_in_current_ymm[0].location.source_buffer.range.offset;
        offset_for_ymm_load = first_source_offset;

        if (float_expanded_bytes <= 16) {
            return;
        }

        int expanded = 0;
        int source_bytes_for_lower_half = 0;

        for (int i = 0; i < attributes_collected_for_current_ymm; i++) {
            auto ads = attributes_in_current_ymm[i];
            int this_expanded = ads.num_output_dwords * 4;
            int this_source = (ads.status == AttributeStatus.AwaitingIndexedInsert)
                ? ads.element_size
                : ads.location.source_buffer.range.length;

            if (expanded + this_expanded <= 16) {
                source_bytes_for_lower_half += this_source;
                expanded += this_expanded;
            } else {
                // This attribute straddles the lane boundary. Figure out how
                // many of its elements fit in the remaining lower-half space.
                int remaining_lower_bytes = 16 - expanded;
                int elements_in_lower = remaining_lower_bytes / 4;
                source_bytes_for_lower_half += elements_in_lower * ads.element_size;
                break;
            }
        }

        offset_for_ymm_load = first_source_offset - (16 - source_bytes_for_lower_half);
    };

    vds.foreach_attribute((ref AttributeDecodeState ads) {
        if (ads.status == AttributeStatus.Unused) {
            return;
        }

        int this_size = ads.num_output_dwords * 4;
        if (float_expanded_bytes + this_size > 32 && attributes_collected_for_current_ymm > 0) {
            compute_ymm_load_offset();
            mark_and_load_attributes();
            float_expanded_bytes = 0;
        }

        if (ads.status == AttributeStatus.AwaitingIndexedInsert) {
            current_offset_within_source_stream += ads.element_size;
        } else {
            current_offset_within_source_stream += ads.location.source_buffer.range.length;
        }
        attributes_in_current_ymm[attributes_collected_for_current_ymm] = &ads;
        attributes_collected_for_current_ymm++;
        float_expanded_bytes += this_size;
    });

    if (attributes_collected_for_current_ymm != 0) {
        compute_ymm_load_offset();
        mark_and_load_attributes();
    }
}

void align_attributes_for_float_expansion(Code code, VertexDecodeState* vds) {
    int ymms_to_align = 0; // bitmask of YMM indices to align
    int ymms_seen = 0;

    vds.foreach_attribute((ref AttributeDecodeState ads) {
        if (ads.status == AttributeStatus.AwaitingAlignment
         || ads.status == AttributeStatus.AwaitingIndexedInsert) {
            ymms_to_align |= 1 << ads.location.ymm.index;
        }

        bool ymm_seen = ymms_seen.bit(ads.location.ymm.index);
        if (!ymm_seen) {
            // horrible code but ill fix later
            YMM licm_ymm = code.register_licm_ymm([
                3,  2,  1,  0,
                7,  6,  5,  4,
                11, 10, 9,  8,
                15, 14, 13, 12,
                19, 18, 17, 16,
                23, 22, 21, 20,
                27, 26, 25, 24,
                31, 30, 29, 28
            ]);

            code.assign_vpshufb_mask_to_ymm(YMM(ads.location.ymm.index), licm_ymm);

            ymms_seen |= 1 << ads.location.ymm.index;
        }
    });

    while (ymms_to_align != 0) {
        int ymm_to_align = cast(int) ymms_to_align.bfs();

        // Build the vpshufb control mask for this YMM
        u8[32] vpshufb_control_mask;

        // Initialize vpshufb control mask to all 0xFF (which zeroes out the bytes in the result)
        for (u8 i = 0; i < 32; i++) {
            vpshufb_control_mask[i] = 0xff;
        }

        // We need to find all fields in the vds that live in this YMM, and find a new home for them
        // within this YMM. We will pack them towards the start of the YMM, bump-allocator style.
        u8 next_free_byte = 0;
        vds.foreach_attribute((ref AttributeDecodeState ads) {
            if (ads.status != AttributeStatus.AwaitingAlignment
             && ads.status != AttributeStatus.AwaitingIndexedInsert) {
                return;
            }

            if (ads.location.ymm.index != ymm_to_align) {
                return;
            }

            u8 attribute_length = ads.location.ymm.range.length;
            u8 attribute_offset = ads.location.ymm.range.offset;
            u8 element_size     = ads.element_size;

            u8 alignment = 4;

            // Align the next free byte to the attribute's alignment requirement
            if (next_free_byte % alignment != 0) {
                next_free_byte += alignment - (next_free_byte % alignment);
            }

            // Update the attribute's location to its new offset
            ads.location.ymm.range.offset = next_free_byte;

            if (ads.status == AttributeStatus.AwaitingIndexedInsert) {
                // Reserve dword-aligned space but leave vpshufb mask as 0xFF (zeroed output).
                // Scalar code will insert the dequantized data later.
                next_free_byte += ads.num_output_dwords * 4;
                return;
            }

            // Copy all elements from their old location to their new location in the control mask,
            // while swapping endianness at the same time
            for (u8 i = 0; i < attribute_length; i += element_size) {
                for (u8 j = 0; j < element_size; j++) {
                    vpshufb_control_mask[next_free_byte + j] = cast(u8) (attribute_offset + (element_size - 1 - j) + i);
                }

                next_free_byte += 4; // float expansion to 4 bytes
            }
        });

        YMM licm_ymm = code.vpshufb_mask_for(YMM(cast(u8) ymm_to_align));
        code.update_licm_ymm(licm_ymm, vpshufb_control_mask);

        ymms_to_align &= ~(1 << ymm_to_align);
    }
}

private bool ops_equivalent(ref Op a, ref Op b) {
    if (a.kind != b.kind) {
        return false;
    }

    final switch (a.kind) {
        case OpKind.Sext:
            return a.sext.from == b.sext.from;
        case OpKind.Zext:
            return a.zext.from == b.zext.from;
        case OpKind.Mul:
            return a.mul.factor == b.mul.factor;
        case OpKind.DequantizeColor:
            return a.dequantize_color.format == b.dequantize_color.format;
        case OpKind.CvtToFloat:
            return true;
        case OpKind.Store:
            return a.store.dest_offset == b.store.dest_offset;
        case OpKind.IndexedLoad:
            return false; // IndexedLoad ops are never merged
    }
}

// Resolve the address of an indexed array element into addr_reg.
// Reads the index from [rdi + stream_offset], then computes:
//   addr_reg = host_bases[array_number] + index * strides[array_number]
private void emit_resolve_indexed_address(Code code, ref IndexedLoad il, R64 addr_reg) {
    auto idx = code.allocate_register();

    // Load index from vertex stream
    // Cast to uint to avoid D overload resolution matching the ubyte segment
    // parameter in Address(T register, ubyte segment, uint offset = 0).
    if (il.index_size == 1) {
        code.movzx(idx, code.bytePtr(Code.SOURCE_REG64, cast(uint) il.stream_offset));
    } else {
        code.movbe(idx.cvt16(), code.wordPtr(Code.SOURCE_REG64, cast(uint) il.stream_offset));
        code.movzx(idx, idx.cvt16());
    }

    // Multiply index by stride: idx *= strides[array_number]
    code.imul(idx, code.dwordPtr(Code.ARRAY_INFO_REG64, 128 + il.array_number * 4));

    // Load host base pointer and add offset: addr_reg = host_bases[array_number] + idx
    code.mov(addr_reg, code.qwordPtr(Code.ARRAY_INFO_REG64, il.array_number * 8));
    code.add(addr_reg, idx.cvt64());

    code.free_register(idx);
}

// Emit scalar loads for an indexed coord or normal attribute.
// For each component, loads from [addr_reg + i*comp_size], endian-swaps,
// sign/zero extends, converts to float, optionally scales, and inserts
// into the target YMM lane via vmovd -> vpbroadcastd -> vblendps.
private void emit_indexed_coord_or_normal(Code code, ref IndexedLoad il, YMM ymm,
                                           R64 addr_reg, VertexDecodeState* vds) {
    u8 comp_size;
    bool is_signed;
    bool is_float;

    if (il.attr_kind == IndexedAttrKind.Coord) {
        comp_size = coord_size(il.coord_format);
        is_signed = (il.coord_format == CoordFormat.S8 || il.coord_format == CoordFormat.S16);
        is_float = (il.coord_format == CoordFormat.F32);
    } else {
        comp_size = normal_size(il.normal_format);
        is_signed = true; // normals are always signed
        is_float = (il.normal_format == NormalFormat.F32);
    }

    auto val = code.allocate_register();
    auto xmm_tmp = XMM(vds.tmp_ymm().index, vds.tmp_ymm().extended);
    auto ymm_tmp = vds.tmp_ymm();

    // Set up scale factor if needed
    bool needs_scale = !is_float && il.scale != 1.0f;
    auto xmm_scale = XMM(vds.tmp_ymm2().index, vds.tmp_ymm2().extended);
    if (needs_scale) {
        auto scale_reg = code.allocate_register();
        code.mov(scale_reg, force_cast!uint(il.scale));
        code.vmovd(xmm_scale, scale_reg);
        code.free_register(scale_reg);
    }

    int base_lane = il.ymm_byte_offset / 4;

    for (int i = 0; i < il.component_count; i++) {
        int offset = (il.first_component_index + i) * comp_size;

        // Load + endian swap + sign/zero extend
        if (comp_size == 1) {
            if (is_signed) {
                code.movsx(val, code.bytePtr(addr_reg, offset));
            } else {
                code.movzx(val, code.bytePtr(addr_reg, offset));
            }
        } else if (comp_size == 2) {
            code.movbe(val.cvt16(), code.wordPtr(addr_reg, offset));
            if (is_signed) {
                code.movsx(val, val.cvt16());
            } else {
                code.movzx(val, val.cvt16());
            }
        } else {
            // 4-byte: F32, just movbe to get big-endian float bits
            code.movbe(val, code.dwordPtr(addr_reg, offset));
        }

        // Int->float conversion (skip for F32)
        code.vmovd(xmm_tmp, val);
        if (!is_float) {
            code.vcvtdq2ps(xmm_tmp, xmm_tmp);
            if (needs_scale) {
                code.vmulps(xmm_tmp, xmm_tmp, xmm_scale);
            }
        }

        // Insert into YMM lane: vpbroadcastd -> vblendps
        code.vpbroadcastd(ymm_tmp, xmm_tmp);
        code.vblendps(ymm, ymm, ymm_tmp, cast(u8)(1 << (base_lane + i)));
    }

    code.free_register(val);
}

// Emit scalar load + dequant for an indexed color attribute.
// Loads raw color data from [addr_reg], dequantizes to RGBA u32,
// and inserts into the target YMM lane.
private void emit_indexed_color_dequant(Code code, ref IndexedLoad il, YMM ymm,
                                         R64 addr_reg, VertexDecodeState* vds) {
    auto val = code.allocate_register();
    auto res = code.allocate_register();
    auto t1  = code.allocate_register();
    auto xmm_tmp = XMM(vds.tmp_ymm().index, vds.tmp_ymm().extended);
    auto ymm_tmp = vds.tmp_ymm();

    int lane = il.ymm_byte_offset / 4;

    final switch (il.color_format) {
        case ColorFormat.RGBA8888: {
            // 4 bytes, just movbe for endian swap
            code.movbe(val, code.dwordPtr(addr_reg, 0));
            break;
        }
        case ColorFormat.RGB888: {
            // 3 bytes: form byte[2]<<24 | byte[1]<<16 | byte[0]<<8 | 0xFF
            code.movzx(val, code.bytePtr(addr_reg, 2));
            code.shl(val, 24);
            code.movzx(res, code.bytePtr(addr_reg, 1));
            code.shl(res, 16);
            code.or(val, res);
            code.movzx(res, code.bytePtr(addr_reg, 0));
            code.shl(res, 8);
            code.or(val, res);
            code.or(val, cast(uint) 0xFF);
            break;
        }
        case ColorFormat.RGB888x: {
            // 4 bytes: LE load gives byte[3]<<24|byte[2]<<16|byte[1]<<8|byte[0], replace low byte with 0xFF
            code.mov(val, code.dwordPtr(addr_reg, 0));
            code.and(val, cast(uint) 0xFFFFFF00);
            code.or(val, cast(uint) 0xFF);
            break;
        }
        case ColorFormat.RGB565: {
            // 2 bytes: load big-endian u16, dequant to R<<24 | G<<16 | B<<8 | 0xFF
            code.movbe(val.cvt16(), code.wordPtr(addr_reg, 0));
            code.movzx(val, val.cvt16());

            code.mov(res, val);
            code.shl(res, 27);
            code.mov(t1, val);
            code.and(t1, cast(uint) 63488);
            code.shl(val, 13);
            code.and(val, cast(uint) 16515072);
            code.or(val, res);
            code.mov(res, t1);
            code.add(res, val);
            code.add(res, cast(uint) 255);
            code.mov(val, res);
            break;
        }
        case ColorFormat.RGBA4444: {
            // 2 bytes: load big-endian u16, dequant to R<<24 | G<<16 | B<<8 | A
            code.movbe(val.cvt16(), code.wordPtr(addr_reg, 0));
            code.movzx(val, val.cvt16());

            code.mov(t1, val);
            code.shl(t1, 28);
            auto t2 = code.allocate_register();
            code.mov(t2, val);
            code.shr(t2, 8);
            code.and(t2, cast(uint) 0xFFFFFFF0);
            code.mov(res, val);
            code.shl(res, 16);
            code.and(res, cast(uint) 15728640);
            code.or(res, t1);
            code.shl(val, 4);
            code.and(val, cast(uint) 61440);
            code.or(res, val);
            code.or(res, t2);
            code.mov(val, res);
            code.free_register(t2);
            break;
        }
        case ColorFormat.RGBA6666: {
            // 3 bytes: load and form 24-bit value, dequant to R<<24 | G<<16 | B<<8 | A
            code.movzx(val, code.bytePtr(addr_reg, 0));
            code.shl(val, 16);
            code.movzx(res, code.bytePtr(addr_reg, 1));
            code.shl(res, 8);
            code.or(val, res);
            code.movzx(res, code.bytePtr(addr_reg, 2));
            code.or(val, res);

            code.mov(t1, val);
            code.shl(t1, 26);
            auto t2 = code.allocate_register();
            code.mov(t2, val);
            code.shr(t2, 16);
            code.and(t2, cast(uint) 252);
            code.mov(res, val);
            code.shl(res, 12);
            code.and(res, cast(uint) 16515072);
            code.or(res, t1);
            code.shr(val, 2);
            code.and(val, cast(uint) 64512);
            code.or(res, val);
            code.or(res, t2);
            code.mov(val, res);
            code.free_register(t2);
            break;
        }
    }

    // Insert color u32 into YMM lane
    code.vmovd(xmm_tmp, val);
    code.vpbroadcastd(ymm_tmp, xmm_tmp);
    code.vblendps(ymm, ymm, ymm_tmp, cast(u8)(1 << lane));

    code.free_register(val);
    code.free_register(res);
    code.free_register(t1);
}

// Emit all indexed loads targeting a given YMM register.
private void emit_indexed_loads_for_ymm(Code code, ref Op[] ops, YMM ymm, VertexDecodeState* vds) {
    foreach (ref op; ops) {
        if (op.kind != OpKind.IndexedLoad || op.ymm_index != ymm.index) {
            continue;
        }

        auto addr_reg = code.allocate_register();
        emit_resolve_indexed_address(code, op.indexed_load, addr_reg.cvt64());

        if (op.indexed_load.attr_kind == IndexedAttrKind.Color) {
            emit_indexed_color_dequant(code, op.indexed_load, ymm, addr_reg.cvt64(), vds);
        } else {
            emit_indexed_coord_or_normal(code, op.indexed_load, ymm, addr_reg.cvt64(), vds);
        }

        code.free_register(addr_reg);
    }
}

void dequantize_ops(Code code, VertexDecodeState* vds, VertexFormat format) {
    // // First, create all the ops needed to dequantize a given vertex format and decode state.
    auto ops = create_parallel_ops(format, vds);

    // // Merge identical ops that touch disjoint regions by OR-ing their masks.
    // Op[] merged;
    // foreach (ref op; ops) {
    //     bool merged_existing = false;
    //     foreach (ref existing; merged) {
    //         if (!ops_equivalent(existing, op) || op.ymm_index != existing.ymm_index) {
    //             continue;
    //         }

    //         assert_hollywood((existing.source_mask & op.source_mask) == 0,
    //             "expected disjoint masks when merging identical ops");
    //         existing.source_mask |= op.source_mask;
    //         merged_existing = true;
    //         break;
    //     }

    //     if (!merged_existing) {
    //         merged ~= op;
    //     }
    // }

    int current_dest_stream_offset = 0;
    foreach (ymm; vds.allocated_ymms) {
        // Let's handle extension first. Zero-extension was already handled by align_attributes_for_float_expansion.
        // But we need to do sign_extension.

        bool needs_sign_extension      = false;
        bool needs_scaling             = false;

        u64 active_fields_in_ymm = 0;
        foreach (ref op; ops) {
            if (op.ymm_index == ymm.index) {
                active_fields_in_ymm |= op.source_mask;
            }
        }

        u64 active_fields_in_ymm_that_need_vcvtdq2ps = 0;
        
        int blend_control = 0;
        auto licm_entry = code.vpshufb_mask_for(YMM(ymm.index));
        auto licm_value = code.licm_value_for_entry(licm_entry);

        u8[32] vpblendvb_mask;
        memset(&vpblendvb_mask[0], 0, vpblendvb_mask.length);

        foreach (ref op; ops) {
            if (op.kind == OpKind.Sext && op.ymm_index == ymm.index) {
                needs_sign_extension = true;

                // Modify the vpshufb mask to duplciate the upper byte of this attribute into the bytes above it
                int attribute_bytes = size_to_bytes(op.sext.from);
                int num_bytes_to_duplicate = 4 - attribute_bytes;
                u64 mask_to_process = op.source_mask;

                while (mask_to_process != 0) {
                    int source_index = cast(int) mask_to_process.bsf();

                    u8 licm_to_dupe = licm_value[source_index + (attribute_bytes - 1)];
                    for (int j = 0; j <= num_bytes_to_duplicate - 1; j++) {
                        licm_value[source_index + attribute_bytes + j] = licm_to_dupe;
                        vpblendvb_mask[source_index + attribute_bytes + j] = 0xFF;
                    }

                    mask_to_process &= ~(0xFUL << (source_index));
                }

                
                // for (u8 i = 0; i < attribute_bytes; i++) {
                //     u8 source_byte_index = cast(u8) (op.source_mask >> (i * 8)) & 0xFF;
                //     for (int j = i + 1; j < attribute_bytes; j++) {
                //         licm_value[source_byte_index + j] = cast(u8) (source_byte_index + (attribute_bytes - 1));
                //         blend_control |= (1 << (source_byte_index + j));
                //     }
                // }

            }

            if (op.kind == OpKind.DequantizeColor && op.ymm_index == ymm.index) {
                // The alignment pass endian-swapped these bytes into [last, ..., first].
                // For colors, the big-endian value's bits(0,7) = last stream byte = R (MSB of u32).
                // The endian swap already produces the correct LE u32 for RGBA8888 (passthrough).
                // For RGB888/RGB888x, we need to fix up the alpha byte and drop the pad.
                int n = cast(int) op.source_mask.bsf();
                final switch (op.dequantize_color.format) {
                    case ColorFormat.RGB888: {
                        // Endian swap: [o+2, o+1, o+0, 0xFF].
                        // Need LE u32 [A, B, G, R] = [0x80, o+0, o+1, o+2].
                        u8 b0 = licm_value[n+0]; // o+2
                        u8 b1 = licm_value[n+1]; // o+1
                        u8 b2 = licm_value[n+2]; // o+0
                        licm_value[n+0] = 0x80;
                        licm_value[n+1] = b2;    // o+0
                        licm_value[n+2] = b1;    // o+1
                        licm_value[n+3] = b0;    // o+2
                        break;
                    }
                    case ColorFormat.RGB888x: {
                        // Endian swap: [o+3, o+2, o+1, o+0]. Pad byte is o+0 (first stream byte).
                        // Need LE u32 [A, B, G, R] = [0x80, o+1, o+2, o+3].
                        u8 x0 = licm_value[n+0]; // o+3
                        u8 x1 = licm_value[n+1]; // o+2
                        u8 x2 = licm_value[n+2]; // o+1
                        licm_value[n+0] = 0x80;
                        licm_value[n+1] = x2;    // o+1
                        licm_value[n+2] = x1;    // o+2
                        licm_value[n+3] = x0;    // o+3
                        break;
                    }
                    case ColorFormat.RGBA8888:
                        // Endian swap already correct — passthrough.
                        break;
                    case ColorFormat.RGB565:
                    case ColorFormat.RGBA4444:
                    case ColorFormat.RGBA6666:
                        // Dequantization for these will be handled in GPR-land,
                        // following what clang emits for similar operations.
                        break;
                }
            }

            if (op.kind == OpKind.CvtToFloat && op.ymm_index == ymm.index) {
                active_fields_in_ymm_that_need_vcvtdq2ps |= op.source_mask;
            }

            needs_scaling |= op.kind == OpKind.Mul && op.ymm_index == ymm.index;
        }


        bool needs_vcvtdq2ps           = active_fields_in_ymm_that_need_vcvtdq2ps != 0;
        bool all_fields_need_vcvtdq2ps = active_fields_in_ymm_that_need_vcvtdq2ps == active_fields_in_ymm;
        
        code.update_licm_ymm(licm_entry, licm_value);
        code.vpshufb(ymm, ymm, licm_entry);


        if (needs_sign_extension) {
            code.vpcmpgtb(vds.tmp_ymm(), code.ymmzero(), ymm);
            code.vpblendvb(ymm, ymm, vds.tmp_ymm(), code.register_licm_ymm(vpblendvb_mask));
        }

        if (needs_vcvtdq2ps) {
            if (all_fields_need_vcvtdq2ps) {
                code.vcvtdq2ps(ymm, ymm);
            } else {
                // Only some lanes need int->float. Convert in a temp and blend back.
                code.vcvtdq2ps(vds.tmp_ymm(), ymm);
                
                u8 blend_mask = 0;
                u64 remaining = active_fields_in_ymm_that_need_vcvtdq2ps;
                
                while (remaining != 0) {
                    int bit = cast(int) remaining.bsf();
                    blend_mask |= cast(u8)(1 << (bit / 4));
                    remaining &= ~(0xFUL << (bit & ~0x3));
                }

                code.vblendps(ymm, ymm, vds.tmp_ymm(), blend_mask);
            }
        }

        if (needs_scaling) {
            // Let's form the YMM scale factor
            float[8] scale_factors = [1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f];

            foreach (ref op; ops) {
                if (op.kind == OpKind.Mul && op.ymm_index == ymm.index) {
                    // Loop through all elements that this op touches, and set their scale factor
                    u64 mask = op.source_mask;
                    while (mask != 0) {
                        int byte_index = cast(int) mask.bfs();
                        int element_index = byte_index / 4;
                        scale_factors[element_index] = op.mul.factor;

                        mask &= ~(0xFUL << (byte_index & ~0x3));
                    }
                }
            }

            YMM scale_ymm = code.register_licm_ymm(cast(u8[32]) scale_factors);
            code.vmulps(ymm, ymm, scale_ymm);
        }

        // Insert any indexed attribute values into the YMM before storing.
        emit_indexed_loads_for_ymm(code, ops, ymm, vds);

        // And store!
        code.vmovups(code.ymmwordPtr(rsi, current_dest_stream_offset), ymm);

        // Post-store fixups for color attributes in this YMM.
        foreach (ref op; ops) {
            if (op.kind != OpKind.DequantizeColor || op.ymm_index != ymm.index)
                continue;

            int n = cast(int) op.source_mask.bsf();
            int color_offset = current_dest_stream_offset + n;

            final switch (op.dequantize_color.format) {
                case ColorFormat.RGB888:
                case ColorFormat.RGB888x:
                    // Alpha byte fixup: write 0xFF to the alpha byte position.
                    code.mov(code.bytePtr(rsi, color_offset), cast(u8) 0xFF);
                    break;

                case ColorFormat.RGBA8888:
                    // Already correct from vpshufb endian swap.
                    break;

                case ColorFormat.RGB565: {
                    // Dequantize packed RGB565 u16 → R<<24 | G<<16 | B<<8 | 0xFF
                    auto val = code.allocate_register(); // input value
                    auto res = code.allocate_register(); // result accumulator
                    auto t1  = code.allocate_register(); // temp

                    code.mov(val, code.dwordPtr(rsi, color_offset));

                    code.mov(res, val);
                    code.shl(res, 27);          // res = (val & 0x1F) << 27   (R bits)
                    code.mov(t1, val);
                    code.and(t1, cast(uint) 63488);      // t1 = val & 0xF800        (B bits)
                    code.shl(val, 13);
                    code.and(val, cast(uint) 16515072);  // val = (val << 13) & 0xFC0000 (G bits)
                    code.or(val, res);           // val = R | G
                    code.mov(res, t1);
                    code.add(res, val);          // res = R | G | B
                    code.add(res, cast(uint) 255); // res |= 0xFF (alpha)

                    code.mov(code.dwordPtr(rsi, color_offset), res);

                    code.free_register(val);
                    code.free_register(res);
                    code.free_register(t1);
                    break;
                }

                case ColorFormat.RGBA4444: {
                    // Dequantize packed RGBA4444 u16 → R<<24 | G<<16 | B<<8 | A
                    auto val = code.allocate_register(); // input value
                    auto res = code.allocate_register(); // result accumulator
                    auto t1  = code.allocate_register(); // temp
                    auto t2  = code.allocate_register(); // temp

                    code.mov(val, code.dwordPtr(rsi, color_offset));

                    code.mov(t1, val);
                    code.shl(t1, 28);            // t1 = (val & 0xF) << 28    (R bits)
                    code.mov(t2, val);
                    code.shr(t2, 8);
                    code.and(t2, cast(uint) 0xFFFFFFF0); // t2 = (val >> 8) & ~0xF  (A bits)
                    code.mov(res, val);
                    code.shl(res, 16);
                    code.and(res, cast(uint) 15728640);  // res = (val << 16) & 0xF00000 (G bits)
                    code.or(res, t1);            // res = R | G
                    code.shl(val, 4);
                    code.and(val, cast(uint) 61440);     // val = (val << 4) & 0xF000 (B bits)
                    code.or(res, val);           // res = R | G | B
                    code.or(res, t2);            // res = R | G | B | A

                    code.mov(code.dwordPtr(rsi, color_offset), res);

                    code.free_register(val);
                    code.free_register(res);
                    code.free_register(t1);
                    code.free_register(t2);
                    break;
                }

                case ColorFormat.RGBA6666: {
                    // Dequantize packed RGBA6666 u24 → R<<24 | G<<16 | B<<8 | A
                    auto val = code.allocate_register(); // input value
                    auto res = code.allocate_register(); // result accumulator
                    auto t1  = code.allocate_register(); // temp
                    auto t2  = code.allocate_register(); // temp

                    code.mov(val, code.dwordPtr(rsi, color_offset));

                    code.mov(t1, val);
                    code.shl(t1, 26);            // t1 = (val & 0x3F) << 26   (R bits)
                    code.mov(t2, val);
                    code.shr(t2, 16);
                    code.and(t2, cast(uint) 252);        // t2 = (val >> 16) & 0xFC (A bits)
                    code.mov(res, val);
                    code.shl(res, 12);
                    code.and(res, cast(uint) 16515072);  // res = (val << 12) & 0xFC0000 (G bits)
                    code.or(res, t1);            // res = R | G
                    code.shr(val, 2);
                    code.and(val, cast(uint) 64512);     // val = (val >> 2) & 0xFC00 (B bits)
                    code.or(res, val);           // res = R | G | B
                    code.or(res, t2);            // res = R | G | B | A

                    code.mov(code.dwordPtr(rsi, color_offset), res);

                    code.free_register(val);
                    code.free_register(res);
                    code.free_register(t1);
                    code.free_register(t2);
                    break;
                }
            }
        }

        // Advance by the actual float-expanded output size of this YMM,
        // not the full 32 bytes. This keeps the output tightly packed so
        // it matches the DestFormat layout.
        int ymm_output_size = 0;
        vds.foreach_attribute((ref AttributeDecodeState ads) {
            if (ads.location.kind != LocationType.Ymm) return;
            if (ads.location.ymm.index != ymm.index) return;
            int end = ads.location.ymm.range.offset + ads.num_output_dwords * 4;
            if (end > ymm_output_size) ymm_output_size = end;
        });
        current_dest_stream_offset += ymm_output_size;
    }

    // We'll handle quantization constants later.
}

DestFormat make_dest_format(VertexFormat format) {
    DestFormat dest_format = make_empty_dest_format();

    auto vcd = &format.vertex_descriptors[format.current_vat];
    auto vat = &format.vats[format.current_vat];
    int current_offset;

    if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
        dest_format.position_matrix_index_offset = current_offset;
        current_offset += 4;
    }

    if (vcd.position_location != VertexAttributeLocation.NotPresent) {
        dest_format.position_offset = current_offset;
        dest_format.position_count  = 1;

        current_offset += 4 * vat.position_count;
    }

    if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
        dest_format.normal_offset = current_offset;
        dest_format.normal_count  = 1;

        current_offset += 4 * vat.normal_count;
    }

    for (int c = 0; c < 2; c++) {
        if (vcd.color_location[c] == VertexAttributeLocation.NotPresent) continue;

        dest_format.color_offset[c] = current_offset;
        dest_format.color_count[c]  = 1;

        current_offset += 4;
    }

    for (int t = 0; t < 8; t++) {
        if (vcd.texcoord_location[t] == VertexAttributeLocation.NotPresent) continue;

        dest_format.texcoord_offset[t] = current_offset;
        dest_format.texcoord_count[t]  = 1;

        current_offset += 4 * vat.texcoord_count[t];
    }

    dest_format.stride = current_offset;
    return dest_format;
}

DestFormat emit_vertex(Code code, VertexFormat format) {
    VertexDecodeState vds = construct_vertex_decode_state(format);
    allocate_ymms_for_attributes_unaligned(code, &vds);
    align_attributes_for_float_expansion(code, &vds);
    dequantize_ops(code, &vds, format);

    return make_dest_format(format);
}
