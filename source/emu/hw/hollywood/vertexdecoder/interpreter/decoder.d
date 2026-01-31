module emu.hw.hollywood.vertexdecoder.interpreter.decoder;

import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.types;
import util.bitop;
import util.force_cast;
import util.log;
import util.number;

/// Decode a vertex stream into caller-provided buffers. No detess/primitive assembly here.
final class VertexInterpreterDecoder {
    VertexDecodeResult decode_vertices(const ubyte* stream,
                                       size_t length,
                                       ref VertexFormat state,
                                       Vertex* out_vertices,
                                       size_t max_vertices) {
        VertexDecodeResult result;
        size_t offset = 0;

        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];

        int emitted = 0;

        while (offset < length && emitted < max_vertices && emitted < state.number_of_expected_vertices) {
            Vertex v;

            if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
                v.position_matrix_index = read_from_shape_data_buffer_direct(stream, offset, 1);
                offset += 1;
            } else {
                v.position_matrix_index = -1;
            }

            // Skip texcoord matrix indices if present
            for (int j = 0; j < 8; j++) {
                if (vcd.texcoord_matrix_location[j] != VertexAttributeLocation.NotPresent) {
                    offset += 1;
                }
            }
            
            decode_position(stream, offset, vcd, vat, state, v);
            decode_normal(stream, offset, vcd, vat, v, state);
            decode_colors(stream, offset, vcd, vat, v, state);
            decode_texcoords(stream, offset, vcd, vat, v, state);

            out_vertices[emitted] = v;
            emitted++;
        }

        result.vertices_emitted = cast(uint) emitted;
        result.dest_format = make_interpreter_dest_format(state);
        return result;
    }

private:
    DestFormat make_interpreter_dest_format(ref VertexFormat state) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        auto vat = &state.vats[state.current_vat];

        DestFormat format = make_empty_dest_format();
        format.stride = cast(int) Vertex.sizeof;

        if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
            format.position_matrix_index_offset = cast(int) Vertex.position_matrix_index.offsetof;
        }

        if (vcd.position_location != VertexAttributeLocation.NotPresent) {
            format.position_offset = cast(int) Vertex.position.offsetof;
            format.position_count = 1;
        }

        if (vcd.normal_location != VertexAttributeLocation.NotPresent) {
            format.normal_offset = cast(int) Vertex.normal.offsetof;
            format.normal_count = 1;
        }

        foreach (c; 0 .. 2) {
            if (vcd.color_location[c] == VertexAttributeLocation.NotPresent) {
                continue;
            }

            format.color_offset[c] = cast(int) (Vertex.color.offsetof + c * u32.sizeof);
            format.color_count[c] = 1;
        }

        foreach (t; 0 .. 8) {
            if (vcd.texcoord_location[t] == VertexAttributeLocation.NotPresent) {
                continue;
            }

            format.texcoord_offset[t] = cast(int) (Vertex.texcoord.offsetof + t * 8);
            format.texcoord_count[t] = 1;
        }

        return format;
    }

    u32 read_from_shape_data_buffer_direct(const ubyte* data, size_t offset, size_t size) {
        u32 result = 0;
        for (int i = 0; i < size; i++) {
            result <<= 8;
            result |= data[offset + i];
        }
        return result;
    }

    u32 read_from_indexed_array(ref VertexFormat state, int array_num, int idx, int attr_offset, size_t size) {
        u32 array_addr = state.array_bases[array_num];
        u32 array_stride = state.array_strides[array_num];
        u32 array_offset = array_addr + (array_stride * idx) + (attr_offset * cast(int) size);

        final switch (size) {
        case 1: return state.mem.physical_read_u8(array_offset);
        case 2: return state.mem.physical_read_u16(array_offset);
        case 3: return state.mem.physical_read_u32(array_offset);
        case 4: return state.mem.physical_read_u32(array_offset);
        }
    }

    size_t calculate_expected_size_of_coord(CoordFormat format) {
        final switch (format) {
            case CoordFormat.U8:  return 1;
            case CoordFormat.S8:  return 1;
            case CoordFormat.U16: return 2;
            case CoordFormat.S16: return 2;
            case CoordFormat.F32: return 4;
        }
    }

    size_t calculate_expected_size_of_color(ColorFormat format) {
        final switch (format) {
            case ColorFormat.RGB565:   return 2;
            case ColorFormat.RGB888:   return 3;
            case ColorFormat.RGB888x:  return 4;
            case ColorFormat.RGBA4444: return 2;
            case ColorFormat.RGBA6666: return 3;
            case ColorFormat.RGBA8888: return 4;
        }
    }

    size_t calculate_expected_size_of_normal(NormalFormat format) {
        final switch (format) {
            case NormalFormat.S8:  return 1;
            case NormalFormat.S16: return 2;
            case NormalFormat.F32: return 4;
        }
    }

    float dequantize_normal(u32 value, NormalFormat format) {
        final switch (format) {
            case NormalFormat.S8:
                return (cast(float) (sext_32((cast(s8) value), 8))) / 64.0;
            
            case NormalFormat.S16:
                return (cast(float) (sext_32((cast(s16) value), 16))) / 16384.0;
            
            case NormalFormat.F32:
                return force_cast!float(value);
        }
    }

    float dequantize_coord(u32 value, CoordFormat format, int shift) {
        final switch (format) {
            case CoordFormat.U8:
                return (cast(float) cast(u8) value) / (cast(float) (1 << shift));
            
            case CoordFormat.S8:
                return (cast(float) (sext_32((cast(s8) value), 8))) / (cast(float) (1 << shift));
            
            case CoordFormat.U16:
                return (cast(float) (cast(u16) value)) / (cast(float) (1 << shift));
            
            case CoordFormat.S16:
                return (cast(float) (sext_32((cast(s16) value), 16))) / (cast(float) (1 << shift));
            
            case CoordFormat.F32:
                return force_cast!float(value) / (cast(float) (1 << shift));
        }
    }

    u32 dequantize_color(u32 value, ColorFormat format) {
        final switch (format) {
            case ColorFormat.RGB565:
                return (value.bits(0, 4) << 3) << 24
                     | (value.bits(5, 10) << 2) << 16
                     | (value.bits(11, 15) << 3) << 8
                     | 0xFF;

            case ColorFormat.RGB888:
                return value.bits(0, 7) << 24
                     | value.bits(8, 15) << 16
                     | value.bits(16, 23) << 8
                     | 0xFF;

            case ColorFormat.RGB888x:
                return value.bits(0, 7) << 24
                     | value.bits(8, 15) << 16
                     | value.bits(16, 23) << 8
                     | 0xFF;

            case ColorFormat.RGBA4444:
                return (value.bits(0, 3) << 4) << 24
                     | (value.bits(4, 7) << 4) << 16
                     | (value.bits(8, 11) << 4) << 8
                     | (value.bits(12, 15) << 4);

            case ColorFormat.RGBA6666:
                return (value.bits(0, 5) << 2) << 24
                     | (value.bits(6, 11) << 2) << 16
                     | (value.bits(12, 17) << 2) << 8
                     | (value.bits(18, 23) << 2);

            case ColorFormat.RGBA8888:
                return value;
        }
    }

    void decode_position(const ubyte* stream, ref size_t offset, VertexDescriptor* vcd, VertexAttributeTable* vat, ref VertexFormat state, ref Vertex v) {
        final switch (vcd.position_location) {
        case VertexAttributeLocation.Direct:
            for (int j = 0; j < vat.position_count; j++) {
                v.position[j] = dequantize_coord(
                    read_from_shape_data_buffer_direct(stream, offset, calculate_expected_size_of_coord(vat.position_format)),
                    vat.position_format, vat.position_shift);
                offset += calculate_expected_size_of_coord(vat.position_format);
            }
            break;
        case VertexAttributeLocation.Indexed8Bit: {
            auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 1);
            for (int j = 0; j < vat.position_count; j++) {
                size_t size = calculate_expected_size_of_coord(vat.position_format);
                u32 vertex_data = read_from_indexed_array(state, 0, array_offset, j, size);
                v.position[j] = dequantize_coord(vertex_data, vat.position_format, vat.position_shift);
            }
            offset += 1;
            break;
        }
        case VertexAttributeLocation.Indexed16Bit: {
            auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 2);
            for (int j = 0; j < vat.position_count; j++) {
                size_t size = calculate_expected_size_of_coord(vat.position_format);
                u32 vertex_data = read_from_indexed_array(state, 0, array_offset, j, size);
                v.position[j] = dequantize_coord(vertex_data, vat.position_format, vat.position_shift);
            }
            offset += 2;
            break;
        }
        case VertexAttributeLocation.NotPresent:
            break;
        }

        if (vat.position_count == 2) {
            v.position[2] = 0.0;
        }
    }

    void decode_normal(const ubyte* stream, ref size_t offset, VertexDescriptor* vcd, VertexAttributeTable* vat, ref Vertex v, ref VertexFormat state) {
        size_t size = calculate_expected_size_of_normal(vat.normal_format);

        final switch (vcd.normal_location) {
        case VertexAttributeLocation.Direct: {
            // Normal (XYZ)
            for (int j = 0; j < 3 && j < vat.normal_count; j++) {
                v.normal[j] = dequantize_normal(
                    read_from_shape_data_buffer_direct(stream, offset, size),
                    vat.normal_format);
                offset += size;
            }
            // Tangent (BinormalT)
            if (vat.normal_count == 9) {
                for (int j = 0; j < 3; j++) {
                    v.binormal_t[j] = dequantize_normal(
                        read_from_shape_data_buffer_direct(stream, offset, size),
                        vat.normal_format);
                    offset += size;
                }
                // Bitangent (BinormalB)
                for (int j = 0; j < 3; j++) {
                    v.binormal_b[j] = dequantize_normal(
                        read_from_shape_data_buffer_direct(stream, offset, size),
                        vat.normal_format);
                    offset += size;
                }
            }
            break;
        }
        case VertexAttributeLocation.Indexed8Bit: {
            auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 1);
            // Normal (XYZ)
            for (int j = 0; j < 3 && j < vat.normal_count; j++) {
                u32 vertex_data = read_from_indexed_array(state, 1, array_offset, j, size);
                v.normal[j] = dequantize_normal(vertex_data, vat.normal_format);
            }
            if (vat.normal_count == 9) {
                // Tangent (BinormalT)
                for (int j = 0; j < 3; j++) {
                    u32 vertex_data = read_from_indexed_array(state, 1, array_offset, 3 + j, size);
                    v.binormal_t[j] = dequantize_normal(vertex_data, vat.normal_format);
                }
                // Bitangent (BinormalB)
                for (int j = 0; j < 3; j++) {
                    u32 vertex_data = read_from_indexed_array(state, 1, array_offset, 6 + j, size);
                    v.binormal_b[j] = dequantize_normal(vertex_data, vat.normal_format);
                }
            }
            offset += 1;
            break;
        }
        case VertexAttributeLocation.Indexed16Bit: {
            auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 2);
            // Normal (XYZ)
            for (int j = 0; j < 3 && j < vat.normal_count; j++) {
                u32 vertex_data = read_from_indexed_array(state, 1, array_offset, j, size);
                v.normal[j] = dequantize_normal(vertex_data, vat.normal_format);
            }
            if (vat.normal_count == 9) {
                // Tangent (BinormalT)
                for (int j = 0; j < 3; j++) {
                    u32 vertex_data = read_from_indexed_array(state, 1, array_offset, 3 + j, size);
                    v.binormal_t[j] = dequantize_normal(vertex_data, vat.normal_format);
                }
                // Bitangent (BinormalB)
                for (int j = 0; j < 3; j++) {
                    u32 vertex_data = read_from_indexed_array(state, 1, array_offset, 6 + j, size);
                    v.binormal_b[j] = dequantize_normal(vertex_data, vat.normal_format);
                }
            }
            offset += 2;
            break;
        }
        case VertexAttributeLocation.NotPresent:
            break;
        }
    }

    void decode_colors(const ubyte* stream,
                       ref size_t offset,
                       VertexDescriptor* vcd,
                       VertexAttributeTable* vat,
                       ref Vertex v,
                       ref VertexFormat state) {
        for (int j = 0; j < 2; j++) {
            final switch (vcd.color_location[j]) {
            case VertexAttributeLocation.Direct: {
                size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                u32 color_data = read_from_shape_data_buffer_direct(stream, offset, size);
                v.color[j] = dequantize_color(color_data, vat.color_format[j]);
                offset += size;
                break;
            }

            case VertexAttributeLocation.Indexed8Bit: {
                auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 1);
                size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                u32 color_data = read_from_indexed_array(state, j + 2, array_offset, 0, size);
                v.color[j] = dequantize_color(color_data, vat.color_format[j]);
                offset += 1;
                break;
            }

            case VertexAttributeLocation.Indexed16Bit: {
                auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 2);
                size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                u32 color_data = read_from_indexed_array(state, j + 2, array_offset, 0, size);
                v.color[j] = dequantize_color(color_data, vat.color_format[j]);
                offset += 2;
                break;
            }

            case VertexAttributeLocation.NotPresent:
                v.color[j] = 0xFFFFFFFF;
                break;
            }
        }
    }

    void decode_texcoords(const ubyte* stream,
                          ref size_t offset,
                          VertexDescriptor* vcd,
                          VertexAttributeTable* vat,
                          ref Vertex v,
                          ref VertexFormat state) {
        for (int j = 0; j < 8; j++) {
            final switch (vcd.texcoord_location[j]) {
            case VertexAttributeLocation.Direct:
                for (int k = 0; k < vat.texcoord_count[j]; k++) {
                    size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                    u32 texcoord = read_from_shape_data_buffer_direct(stream, offset, size);
                    v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                    offset += size;
                }
                break;
            
            case VertexAttributeLocation.Indexed8Bit: {
                auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 1);
                for (int k = 0; k < vat.texcoord_count[j]; k++) {
                    size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                    u32 texcoord = read_from_indexed_array(state, j + 4, array_offset, k, size);
                    v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                }
                offset += 1;
                break;
            }

            case VertexAttributeLocation.Indexed16Bit: {
                auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 2);
                for (int k = 0; k < vat.texcoord_count[j]; k++) {
                    size_t size = calculate_expected_size_of_coord(vat.texcoord_format[j]);
                    u32 texcoord = read_from_indexed_array(state, j + 4, array_offset, k, size);
                    v.texcoord[j][k] = dequantize_coord(texcoord, vat.texcoord_format[j], vat.texcoord_shift[j]);
                }
                offset += 2;
                break;
            }

            case VertexAttributeLocation.NotPresent:
                break;
            }
        }
    }
}
