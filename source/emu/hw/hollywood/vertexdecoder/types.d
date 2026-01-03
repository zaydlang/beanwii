module emu.hw.hollywood.vertexdecoder.types;

import emu.hw.hollywood.hollywood_types;
import emu.hw.memory.strategy.memstrategy : Mem;
import util.number;

struct VertexDecodeResult {
    uint vertices_emitted;
}

struct VertexDecodeState {
    VertexDescriptor[8]     vertex_descriptors;
    VertexAttributeTable[8] vats;
    int                     bytes_per_vertex;
    ColorConfig[2]          color_configs;
    float[4][2]             color_global;
    u32[16]                 array_bases;
    u32[16]                 array_strides;
    Mem                     mem;
    int                     current_vat;
    int                     number_of_expected_vertices;
}
