module emu.hw.hollywood.vertexdecoder.types;

import emu.hw.hollywood.hollywood_types;
import emu.hw.memory.strategy.memstrategy : Mem;
import util.log;
import util.number;

struct VertexDecodeResult {
    uint vertices_emitted;
    DestFormat dest_format;
}

struct DestFormat {
    int stride;

    int position_offset;
    int normal_offset;
    int position_matrix_index_offset;
    int[2] color_offset;
    int[8] texcoord_offset;

    int position_count;
    int normal_count;
    int[2] color_count;
    int[8] texcoord_count;
}

struct VertexFormat {
    VertexDescriptor[8]     vertex_descriptors;
    VertexAttributeTable[8] vats;
    int                     bytes_per_vertex;
    float[4][2]             color_global;
    u32[16]                 array_bases;
    u32[16]                 array_strides;
    Mem                     mem;
    int                     current_vat;
    int                     number_of_expected_vertices;
}

int size_of_incoming_vertex(ref VertexDescriptor vcd, ref VertexAttributeTable vat) {
    int size = 0;

    final switch (vcd.position_location) {
        case VertexAttributeLocation.Direct:
            size += vat.position_count * cast(int) coord_format_to_bytes(vat.position_format);
            break;
        case VertexAttributeLocation.Indexed8Bit:
            size += 1;
            break;
        case VertexAttributeLocation.Indexed16Bit:
            size += 2;
            break;
        case VertexAttributeLocation.NotPresent:
            break;
    }

    final switch (vcd.normal_location) {
        case VertexAttributeLocation.Direct:
            size += vat.normal_count * cast(int) normal_format_to_bytes(vat.normal_format);
            break;
        case VertexAttributeLocation.Indexed8Bit:
            size += 1;
            break;
        case VertexAttributeLocation.Indexed16Bit:
            size += 2;
            break;
        case VertexAttributeLocation.NotPresent:
            break;
    }

    final switch (vcd.position_normal_matrix_location) {
        case VertexAttributeLocation.Direct:
            size += 1;
            break;
        case VertexAttributeLocation.Indexed8Bit:
        case VertexAttributeLocation.Indexed16Bit:
            error_hollywood("Indexed Matrix location not implemented");
            break;
        case VertexAttributeLocation.NotPresent:
            break;
    }

    foreach (i; 0 .. 8) {
        final switch (vcd.texcoord_matrix_location[i]) {
            case VertexAttributeLocation.Direct:
                size += 1;
                break;
            case VertexAttributeLocation.Indexed8Bit:
            case VertexAttributeLocation.Indexed16Bit:
                error_hollywood("Indexed Matrix location not implemented");
                break;
            case VertexAttributeLocation.NotPresent:
                break;
        }
    }

    foreach (i; 0 .. 2) {
        final switch (vcd.color_location[i]) {
            case VertexAttributeLocation.Direct:
                size += cast(int) color_format_to_bytes(vat.color_format[i]);
                break;
            case VertexAttributeLocation.Indexed8Bit:
                size += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                size += 2;
                break;
            case VertexAttributeLocation.NotPresent:
                break;
        }
    }

    foreach (i; 0 .. 8) {
        final switch (vcd.texcoord_location[i]) {
            case VertexAttributeLocation.Direct:
                size += vat.texcoord_count[i] * cast(int) coord_format_to_bytes(vat.texcoord_format[i]);
                break;
            case VertexAttributeLocation.Indexed8Bit:
                size += 1;
                break;
            case VertexAttributeLocation.Indexed16Bit:
                size += 2;
                break;
            case VertexAttributeLocation.NotPresent:
                break;
        }
    }

    return size;
}

DestFormat make_empty_dest_format() {
    DestFormat format;
    format.position_offset = -1;
    format.normal_offset = -1;
    format.position_matrix_index_offset = -1;

    foreach (i; 0 .. format.color_offset.length) {
        format.color_offset[i] = -1;
    }

    foreach (i; 0 .. format.texcoord_offset.length) {
        format.texcoord_offset[i] = -1;
    }

    return format;
}

private size_t color_format_to_bytes(ColorFormat format) {
    final switch (format) {
        case ColorFormat.RGB565:   return 2;
        case ColorFormat.RGB888:   return 3;
        case ColorFormat.RGB888x:  return 4;
        case ColorFormat.RGBA4444: return 2;
        case ColorFormat.RGBA6666: return 3;
        case ColorFormat.RGBA8888: return 4;
    }
}

private size_t normal_format_to_bytes(NormalFormat format) {
    final switch (format) {
        case NormalFormat.S8:  return 1;
        case NormalFormat.S16: return 2;
        case NormalFormat.F32: return 4;
    }
}
