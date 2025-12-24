module emu.hw.hollywood.hollywood_types;

import bindbc.opengl;
import util.number;

// Re-export from texture module to avoid conflicts
public import emu.hw.hollywood.texture : TextureWrap, TextureType, TextureDescriptor, TexcoordSource;

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


alias GLBool = u8;

struct VertexDescriptor {
    VertexAttributeLocation    position_normal_matrix_location;
    VertexAttributeLocation[8] texcoord_matrix_location;
    VertexAttributeLocation    position_location;
    VertexAttributeLocation    normal_location;
    VertexAttributeLocation[2] color_location;
    VertexAttributeLocation[8] texcoord_location;
}

struct VertexAttributeTable {
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

struct GlAlignedFloat {
    float value;
    alias value this;
    void opAssign(float value) {
        this.value = value;
    }
}

struct TevStage {
    u32 in_color_a;
    u32 in_color_b;
    u32 in_color_c;
    u32 in_color_d;
    u32 color_op;
    u32 in_alfa_a;
    u32 in_alfa_b;
    u32 in_alfa_c;
    u32 in_alfa_d;
    u32 alfa_op;
    u32 color_dest;
    u32 alfa_dest;
    float bias_color;
    float scale_color;
    float bias_alfa;
    float scale_alfa;
    u32 ras_channel_id;
    u32 ras_swap_table_index;
    u32 tex_swap_table_index;
    u32 texmap;
    u32 texcoord;
    u32 texmap_enable;
    u32 clamp_color;
    u32 clamp_alfa;
    u32 kcsel;
    u32 kasel;
}

struct TevConfig {
    align(1):
    TevStage[16] stages;
    GlAlignedFloat[4] reg0;
    GlAlignedFloat[4] reg1;
    GlAlignedFloat[4] reg2;
    GlAlignedFloat[4] reg3;
    GlAlignedFloat[4] k0;
    GlAlignedFloat[4] k1;
    GlAlignedFloat[4] k2;
    GlAlignedFloat[4] k3;
    int num_tev_stages;
    int padding;
    u64 swap_tables;
    float alpha_ref0;
    float alpha_ref1;
    u32 alpha_comp0;
    u32 alpha_comp1;
    u32 alpha_aop;
}

struct TexConfig {
    align(1):
    float[12] dualtex_matrix;
    float[12] tex_matrix;
    GLBool    normalize_before_dualtex;
    u32       texcoord_source;
    u32       texmatrix_size;
    u32       use_stq;
}

struct VertexConfig {
    align(1):
    TexConfig[8] tex_configs;
    int end;
}


struct Texture {
    int texture_id;
    size_t width;
    size_t height;
    TextureWrap wrap_s;
    TextureWrap wrap_t;
    float[12] dualtex_matrix;
    float[12] tex_matrix;
    bool normalize_before_dualtex;
}

struct RenderState {
    float[12] position_matrix;
    float[16] projection_matrix;
    Texture[8] texture;
    TextureDescriptor[8] texture_descriptors;
    VertexConfig vertex_config;
    TevConfig tev_config;
    bool textured;
    int enabled_textures_bitmap;
    int geometry_matrix_idx;
    bool depth_test_enabled;
    bool depth_write_enabled;
    u32 depth_func;
    int cull_mode;
    bool alpha_update_enable;
    bool color_update_enable;
    bool arithmetic_blending_enable;
    int blend_destination;
    int blend_source;
    bool subtractive_additive_toggle;
    bool uses_per_vertex_matrices;
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