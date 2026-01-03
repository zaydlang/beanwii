module emu.hw.hollywood.hollywood_types;

import util.number;

// Re-export from opengl_renderer and texture modules
public import emu.hw.hollywood.opengl.opengl_renderer;
public import emu.hw.hollywood.texture;

alias Texture = OpenGLRenderer.Texture;
alias RenderState = OpenGLRenderer.RenderState;
alias TevConfig = OpenGLRenderer.TevConfig;
alias VertexConfig = OpenGLRenderer.VertexConfig;

enum GXFifoCommand {
    BlittingProcessor = 0x61,
    CommandProcessor  = 0x08,
    TransformUnit     = 0x10,
    
    LoadMtxIdxA       = 0x20,
    LoadMtxIdxB       = 0x28,
    LoadMtxIdxC       = 0x30,
    LoadMtxIdxD       = 0x38,
    
    VSInvalidate      = 0x48,
    NoOp              = 0x00,
    
    DrawQuads         = 0x80,
    DrawTriangles     = 0x90,
    DrawTriangleFan   = 0xA0,
    DrawTriangleStrip = 0x98,
    DrawLines         = 0xA8,
    
    DisplayList       = 0x40,
}

enum State {
    WaitingForCommand,
    WaitingForBPWrite,
    WaitingForCPReg,
    WaitingForCPData,
    WaitingForTransformUnitDescriptor,
    WaitingForTransformUnitData,
    WaitingForLoadMtxIdxData,
    WaitingForNumberOfVertices,
    WaitingForVertexData,
    WaitingForDisplayListAddress,
    WaitingForDisplayListSize,
}

enum VertexAttributeLocation {
    NotPresent = 0,
    Direct = 1,
    Indexed8Bit = 2,
    Indexed16Bit = 3,
}

enum ProjectionMode {
    Perspective = 0,
    Orthographic = 1,
}

enum CoordFormat {
    U8  = 0,
    S8  = 1,
    U16 = 2,
    S16 = 3,
    F32 = 4,
}

enum NormalFormat {
    S8  = 1,
    S16 = 3,
    F32 = 4,
}

enum ColorFormat {
    RGB565   = 0,
    RGB888   = 1,
    RGB888x  = 2,
    RGBA4444 = 3,
    RGBA6666 = 4,
    RGBA8888 = 5,
}

enum MaterialSource {
    FromGlobal = 0,
    FromVertex = 1,
}

enum RasChannelId {
    Color0    = 0,
    Color1    = 1,
    Alpha0    = 2,
    Alpha1    = 3,
    Color0A0  = 4,
    Color0A1  = 5,
    ColorZero = 6,
    AlphaBump = 7,
}


struct VertexDescriptor {
    u32                        raw_vcd_lo;
    u32                        raw_vcd_hi;
    VertexAttributeLocation    position_normal_matrix_location;
    VertexAttributeLocation[8] texcoord_matrix_location;
    VertexAttributeLocation    position_location;
    VertexAttributeLocation    normal_location;
    VertexAttributeLocation[2] color_location;
    VertexAttributeLocation[8] texcoord_location;
}

struct VertexAttributeTable {
    u32 raw_vat_a;
    u32 raw_vat_b;
    u32 raw_vat_c;

    CoordFormat position_format;
    int position_count;
    int position_shift;
    
    NormalFormat normal_format;
    int normal_count;
    int normal_shift;
    ColorFormat[2] color_format;
    int[2] color_count;
    int[2] color_shift;
    CoordFormat[8] texcoord_format;
    int[8] texcoord_count;
    int[8] texcoord_shift;
}

struct Vertex {
    float[3] position;
    float[3] normal;
    float[2][8] texcoord;
    float[4][2] color;
    int position_matrix_index;
}

struct ColorConfig {
    MaterialSource material_src;
}

struct ShapeGroup {
    size_t shared_vertex_start = 0;
    size_t shared_vertex_count = 0;
    size_t shared_index_start = 0;
    size_t shared_index_count = 0;
}

struct Shape {
    Vertex[3] vertices;
}

struct FifoDebugValue {
    u64 value;
    State state;
}

size_t coord_format_to_bytes(CoordFormat format) {
    final switch (format) {
        case CoordFormat.U8:
        case CoordFormat.S8:
            return 1;
        case CoordFormat.U16:
        case CoordFormat.S16:
            return 2;
        case CoordFormat.F32:
            return 4;
    }
}