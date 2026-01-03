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
                                       ref VertexDecodeState state,
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
            decode_normal(stream, offset, vcd, vat);
            decode_colors(stream, offset, vcd, vat, v, state);
            decode_texcoords(stream, offset, vcd, vat, v, state);

            out_vertices[emitted] = v;
            emitted++;
        }

        result.vertices_emitted = cast(uint) emitted;
        return result;
    }

private:
    u32 read_from_shape_data_buffer_direct(const ubyte* data, size_t offset, size_t size) {
        u32 result = 0;
        for (int i = 0; i < size; i++) {
            result <<= 8;
            result |= data[offset + i];
        }
        return result;
    }

    u32 read_from_indexed_array(ref VertexDecodeState state, int array_num, int idx, int attr_offset, size_t size) {
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

    float[4] dequantize_color(u32 value, ColorFormat format, int index) {
        final switch (format) {
            case ColorFormat.RGB565:
                return [
                    (cast(float) (value.bits(0, 4) << 3)) / 0xff,
                    (cast(float) (value.bits(5, 10) << 2)) / 0xff,
                    (cast(float) (value.bits(11, 15) << 3)) / 0xff,
                    1.0
                ];
            
            case ColorFormat.RGB888:
                return [
                    (cast(float) (value.bits(0, 7))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    1.0
                ];
            
            case ColorFormat.RGB888x:
                return [
                    (cast(float) (value.bits(0, 7))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    1.0
                ];
            
            case ColorFormat.RGBA4444:
                return [
                    (cast(float) (value.bits(0, 3) << 4)) / 0xff,
                    (cast(float) (value.bits(4, 7) << 4)) / 0xff,
                    (cast(float) (value.bits(8, 11) << 4)) / 0xff,
                    (cast(float) (value.bits(12, 15) << 4)) / 0xff,
                ];
            
            case ColorFormat.RGBA6666:
                return [
                    (cast(float) (value.bits(0, 5) << 2)) / 0xff,
                    (cast(float) (value.bits(6, 11) << 2)) / 0xff,
                    (cast(float) (value.bits(12, 17) << 2)) / 0xff,
                    (cast(float) (value.bits(18, 23) << 2)) / 0xff,
                ];
            
            case ColorFormat.RGBA8888:
                return [
                    (cast(float) (value.bits(24, 31))) / 0xff,
                    (cast(float) (value.bits(16, 23))) / 0xff,
                    (cast(float) (value.bits(8, 15))) / 0xff,
                    (cast(float) (value.bits(0, 7))) / 0xff,
                ];
        }
    }

    void decode_position(const ubyte* stream, ref size_t offset, VertexDescriptor* vcd, VertexAttributeTable* vat, ref VertexDecodeState state, ref Vertex v) {
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

    void decode_normal(const ubyte* stream, ref size_t offset, VertexDescriptor* vcd, VertexAttributeTable* vat) {
        final switch (vcd.normal_location) {
        case VertexAttributeLocation.Direct: {
            size_t size = calculate_expected_size_of_normal(vat.normal_format);
            for (int j = 0; j < vat.normal_count; j++) {
                read_from_shape_data_buffer_direct(stream, offset, size);
                offset += size;
            }
            break;
        }
        case VertexAttributeLocation.Indexed8Bit:
            read_from_shape_data_buffer_direct(stream, offset, 1);
            offset += 1;
            break;
        case VertexAttributeLocation.Indexed16Bit:
            read_from_shape_data_buffer_direct(stream, offset, 2);
            offset += 2;
            break;
        case VertexAttributeLocation.NotPresent:
            break;
        }
    }

    void decode_colors(const ubyte* stream,
                       ref size_t offset,
                       VertexDescriptor* vcd,
                       VertexAttributeTable* vat,
                       ref Vertex v,
                       ref VertexDecodeState state) {
        for (int j = 0; j < 2; j++) {
            float[4] color;

            final switch (vcd.color_location[j]) {
            case VertexAttributeLocation.Direct: {
                size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                u32 color_data = read_from_shape_data_buffer_direct(stream, offset, size);
                color = dequantize_color(color_data, vat.color_format[j], j);

                if (vat.color_count[j] == 3) {
                    color[3] = 1.0;
                }

                offset += size;
                break;
            }
            
            case VertexAttributeLocation.Indexed8Bit: {
                auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 1);
                size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                u32 color_data = read_from_indexed_array(state, j + 2, array_offset, 0, size);
                color = dequantize_color(color_data, vat.color_format[j], j);

                if (vat.color_count[j] == 3) {
                    color[3] = 1.0;
                }

                offset += 1;
                break;
            }
            
            case VertexAttributeLocation.Indexed16Bit: {
                auto array_offset = read_from_shape_data_buffer_direct(stream, offset, 2);
                size_t size = calculate_expected_size_of_color(vat.color_format[j]);
                u32 color_data = read_from_indexed_array(state, j + 2, array_offset, 0, size);
                color = dequantize_color(color_data, vat.color_format[j], j);

                if (vat.color_count[j] == 3) {
                    color[3] = 1.0;
                }

                offset += 2;
                break;
            }
            
            case VertexAttributeLocation.NotPresent:
                color = [1.0, 1.0, 1.0, 1.0];
                break;
            }

            final switch (state.color_configs[j].material_src) {
                case MaterialSource.FromGlobal:
                    v.color[j] = state.color_global[j];
                    break;
                case MaterialSource.FromVertex:
                    v.color[j] = color;
                    break;
            }
        }
    }

    void decode_texcoords(const ubyte* stream,
                          ref size_t offset,
                          VertexDescriptor* vcd,
                          VertexAttributeTable* vat,
                          ref Vertex v,
                          ref VertexDecodeState state) {
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
