module emu.hw.hollywood.volatile_state;

import util.number;

// Re-export from texture module to avoid conflicts
public import emu.hw.hollywood.texture : TextureWrap, TextureType, TextureDescriptor, TexcoordSource, Color;

alias GLBool = u32;

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
    u32[2] padding;
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
    u64 swap_tables; // 8 * 4 

    int alpha_comp0;
    int alpha_comp1;
    int alpha_aop;
    int alpha_ref0;
    int alpha_ref1;
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
    int max_level;
}

struct RenderState {
    float[12] position_matrix;
    float[12] normal_matrix;
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
    
    u16 efb_src_x;
    u16 efb_src_y;
    u16 efb_src_w;
    u16 efb_src_h;
    u8 clear_color_red;
    u8 clear_color_green;
    u8 clear_color_blue;
    u8 clear_color_alpha;
    u32 clear_depth;
    float[5] viewport;
    
    u8 alpha_comp0;
    u8 alpha_comp1;
    u8 alpha_aop;
    u8 alpha_ref0;
    u8 alpha_ref1;
}
