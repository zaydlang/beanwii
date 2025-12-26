module emu.hw.hollywood.opengl_renderer;

import bindbc.opengl;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.texture;
import util.bitop;
import util.log;
import util.number;
import std.file;
import std.string;

alias GLBool = u32;

struct GlAlignedFloat {
    float value;
    alias value this;

    void opAssign(float value) {
        this.value = value;
    }
}

final class OpenGLRenderer {
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
        u64 swap_tables;

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

    private RenderState render_state;
    private ShapeGroup accumulated_geometry;
    
    private GlObjectManager gl_object_manager;
    
    private GLuint gl_program;
    private int[8] texture_uniform_locations;
    private int position_attr_location = -1;
    private int normal_attr_location = -1;
    private int texcoord_attr_location = -1;
    private int color_attr_location = -1;
    private int matrix_index_attr_location = -1;
    private int position_matrix_uniform_location = -1;
    private int texture_matrix_uniform_location = -1;
    private int matrix_data_uniform_location = -1;
    private int mvp_uniform_location = -1;
    private uint tev_config_block_index = -1;
    private uint vertex_config_block_index = -1;
    private uint persistent_vertex_buffer = 0;
    private uint persistent_tev_buffer = 0;
    private uint persistent_vertex_config_buffer = 0;
    private uint persistent_index_buffer = 0;
    private float[256] general_matrix_ram;
    
    private GLuint efb_fbo;
    private GLuint efb_color_texture;
    private GLuint efb_depth_texture;
    private GLuint xfb_fbo;
    private GLuint xfb_color_texture;
    private GLuint xfb_shader_program;
    private GLuint xfb_vao;
    private GLuint xfb_vbo;
    
    private Vertex* persistent_vertex_ptr = null;
    private uint* persistent_index_ptr = null;
    
    static immutable size_t MAX_VERTICES = 1024 * 1024;
    static immutable size_t MAX_INDICES = MAX_VERTICES * 6;
    
    this(GlObjectManager gl_object_manager) {
        this.gl_object_manager = gl_object_manager;
        render_state = RenderState();
    }
    
    private void flush() {
        if (accumulated_geometry.shared_index_count == 0) {
            return;
        }
       
        flush_and_render(accumulated_geometry);

        accumulated_geometry.shared_index_count = 0;
        accumulated_geometry = ShapeGroup();
    }
    
    Vertex* next_vertex() {
        return allocate_vertex();
    }
    
    uint* next_index() {
        return allocate_index();
    }
    
    void flush_accumulated_batch() {
        flush();
    }
    
    void submit_shape_group(ShapeGroup geometry) {
        if (accumulated_geometry.shared_index_count == 0) {
            accumulated_geometry = geometry;
        } else {
            accumulated_geometry.shared_index_count += geometry.shared_index_count;
        }
    }
    
    void init_geometry_tracking() {
        if (accumulated_geometry.shared_index_count == 0) {
            accumulated_geometry.shared_vertex_start = get_current_vertex_offset();
            accumulated_geometry.shared_index_start = get_current_index_offset();
        }
    }
    
    uint get_local_vertex_index() {
        return cast(uint) (get_current_vertex_offset() - accumulated_geometry.shared_vertex_start);
    }
    
    void finalize_geometry() {
        accumulated_geometry.shared_index_count = get_current_index_offset() - accumulated_geometry.shared_index_start;
        accumulated_geometry.shared_vertex_count = get_current_vertex_offset() - accumulated_geometry.shared_vertex_start;
    }
    
    // Getters for fields that Hollywood needs to read
    bool get_uses_per_vertex_matrices() const {
        return render_state.uses_per_vertex_matrices;
    }
    
    u16 get_efb_src_x() const {
        return render_state.efb_src_x;
    }
    
    u16 get_efb_src_y() const {
        return render_state.efb_src_y;
    }
    
    u16 get_efb_src_w() const {
        return render_state.efb_src_w;
    }
    
    u16 get_efb_src_h() const {
        return render_state.efb_src_h;
    }
    
    ref TextureDescriptor get_texture_descriptor(int i) {
        return render_state.texture_descriptors[i];
    }
    
    int get_geometry_matrix_idx() const {
        return render_state.geometry_matrix_idx;
    }
    
    ref VertexConfig get_vertex_config() {
        return render_state.vertex_config;
    }
    
    ref TevConfig get_tev_config() {
        return render_state.tev_config;
    }
    
    int get_enabled_textures_bitmap() const {
        return render_state.enabled_textures_bitmap;
    }
    
    u8 get_alpha_comp0() const {
        return render_state.alpha_comp0;
    }
    
    u8 get_alpha_comp1() const {
        return render_state.alpha_comp1;
    }
    
    u8 get_alpha_aop() const {
        return render_state.alpha_aop;
    }
    
    u8 get_alpha_ref0() const {
        return render_state.alpha_ref0;
    }
    
    u8 get_alpha_ref1() const {
        return render_state.alpha_ref1;
    }
    
    ref RenderState get_render_state() {
        return render_state;
    }
    
    // RenderState setters
    void set_position_matrix(float[12] value) {
        if (render_state.position_matrix != value) {
            flush();
            render_state.position_matrix = value;
        }
    }
    
    void set_projection_matrix(float[16] value) {
        if (render_state.projection_matrix != value) {
            flush();
            render_state.projection_matrix = value;
        }
    }
    
    void set_textured(bool value) {
        if (render_state.textured != value) {
            flush();
            render_state.textured = value;
        }
    }
    
    void set_enabled_textures_bitmap(int value) {
        if (render_state.enabled_textures_bitmap != value) {
            flush();
            render_state.enabled_textures_bitmap = value;
        }
    }
    
    void set_geometry_matrix_idx(int value) {
        if (render_state.geometry_matrix_idx != value) {
            flush();
            render_state.geometry_matrix_idx = value;
        }
    }
    
    void set_depth_test_enabled(bool value) {
        if (render_state.depth_test_enabled != value) {
            flush();
            render_state.depth_test_enabled = value;
        }
    }
    
    void set_depth_write_enabled(bool value) {
        if (render_state.depth_write_enabled != value) {
            flush();
            render_state.depth_write_enabled = value;
        }
    }
    
    void set_depth_func(u32 value) {
        if (render_state.depth_func != value) {
            flush();
            render_state.depth_func = value;
        }
    }
    
    void set_cull_mode(int value) {
        if (render_state.cull_mode != value) {
            flush();
            render_state.cull_mode = value;
        }
    }
    
    void set_alpha_update_enable(bool value) {
        if (render_state.alpha_update_enable != value) {
            flush();
            render_state.alpha_update_enable = value;
        }
    }
    
    void set_color_update_enable(bool value) {
        if (render_state.color_update_enable != value) {
            flush();
            render_state.color_update_enable = value;
        }
    }
    
    void set_arithmetic_blending_enable(bool value) {
        if (render_state.arithmetic_blending_enable != value) {
            flush();
            render_state.arithmetic_blending_enable = value;
        }
    }
    
    void set_blend_destination(int value) {
        if (render_state.blend_destination != value) {
            flush();
            render_state.blend_destination = value;
        }
    }
    
    void set_blend_source(int value) {
        if (render_state.blend_source != value) {
            flush();
            render_state.blend_source = value;
        }
    }
    
    void set_subtractive_additive_toggle(bool value) {
        if (render_state.subtractive_additive_toggle != value) {
            flush();
            render_state.subtractive_additive_toggle = value;
        }
    }
    
    void set_uses_per_vertex_matrices(bool value) {
        if (render_state.uses_per_vertex_matrices != value) {
            flush();
            render_state.uses_per_vertex_matrices = value;
        }
    }
    
    void set_efb_src_x(u16 value) {
        if (render_state.efb_src_x != value) {
            flush();
            render_state.efb_src_x = value;
        }
    }
    
    void set_efb_src_y(u16 value) {
        if (render_state.efb_src_y != value) {
            flush();
            render_state.efb_src_y = value;
        }
    }
    
    void set_efb_src_w(u16 value) {
        if (render_state.efb_src_w != value) {
            flush();
            render_state.efb_src_w = value;
        }
    }
    
    void set_efb_src_h(u16 value) {
        if (render_state.efb_src_h != value) {
            flush();
            render_state.efb_src_h = value;
        }
    }
    
    void set_clear_color_red(u8 value) {
        if (render_state.clear_color_red != value) {
            flush();
            render_state.clear_color_red = value;
        }
    }
    
    void set_clear_color_green(u8 value) {
        if (render_state.clear_color_green != value) {
            flush();
            render_state.clear_color_green = value;
        }
    }
    
    void set_clear_color_blue(u8 value) {
        if (render_state.clear_color_blue != value) {
            flush();
            render_state.clear_color_blue = value;
        }
    }
    
    void set_clear_color_alpha(u8 value) {
        if (render_state.clear_color_alpha != value) {
            flush();
            render_state.clear_color_alpha = value;
        }
    }
    
    void set_clear_depth(u32 value) {
        if (render_state.clear_depth != value) {
            flush();
            render_state.clear_depth = value;
        }
    }
    
    void set_viewport(float[5] value) {
        if (render_state.viewport != value) {
            flush();
            render_state.viewport = value;
        }
    }
    
    void set_alpha_comp0(u8 value) {
        if (render_state.alpha_comp0 != value) {
            flush();
            render_state.alpha_comp0 = value;
        }
    }
    
    void set_alpha_comp1(u8 value) {
        if (render_state.alpha_comp1 != value) {
            flush();
            render_state.alpha_comp1 = value;
        }
    }
    
    void set_alpha_aop(u8 value) {
        if (render_state.alpha_aop != value) {
            flush();
            render_state.alpha_aop = value;
        }
    }
    
    void set_alpha_ref0(u8 value) {
        if (render_state.alpha_ref0 != value) {
            flush();
            render_state.alpha_ref0 = value;
        }
    }
    
    void set_alpha_ref1(u8 value) {
        if (render_state.alpha_ref1 != value) {
            flush();
            render_state.alpha_ref1 = value;
        }
    }
    
    // Texture setters
    void set_texture_id(int tex_idx, int value) {
        if (render_state.texture[tex_idx].texture_id != value) {
            flush();
            render_state.texture[tex_idx].texture_id = value;
        }
    }
    
    void set_texture_width(int tex_idx, size_t value) {
        if (render_state.texture[tex_idx].width != value) {
            flush();
            render_state.texture[tex_idx].width = value;
        }
    }
    
    void set_texture_height(int tex_idx, size_t value) {
        if (render_state.texture[tex_idx].height != value) {
            flush();
            render_state.texture[tex_idx].height = value;
        }
    }
    
    void set_texture_wrap_s(int tex_idx, TextureWrap value) {
        if (render_state.texture[tex_idx].wrap_s != value) {
            flush();
            render_state.texture[tex_idx].wrap_s = value;
        }
    }
    
    void set_texture_wrap_t(int tex_idx, TextureWrap value) {
        if (render_state.texture[tex_idx].wrap_t != value) {
            flush();
            render_state.texture[tex_idx].wrap_t = value;
        }
    }
    
    void set_texture_dualtex_matrix(int tex_idx, float[12] value) {
        if (render_state.texture[tex_idx].dualtex_matrix != value) {
            flush();
            render_state.texture[tex_idx].dualtex_matrix = value;
        }
    }
    
    void set_texture_tex_matrix(int tex_idx, float[12] value) {
        if (render_state.texture[tex_idx].tex_matrix != value) {
            flush();
            render_state.texture[tex_idx].tex_matrix = value;
        }
    }
    
    void set_texture_normalize_before_dualtex(int tex_idx, bool value) {
        if (render_state.texture[tex_idx].normalize_before_dualtex != value) {
            flush();
            render_state.texture[tex_idx].normalize_before_dualtex = value;
        }
    }
    
    // TexConfig setters (for tex_configs[0-7])
    void set_tex_config_dualtex_matrix(int config_idx, float[12] value) {
        if (render_state.vertex_config.tex_configs[config_idx].dualtex_matrix != value) {
            flush();
            render_state.vertex_config.tex_configs[config_idx].dualtex_matrix = value;
        }
    }
    
    void set_tex_config_tex_matrix(int config_idx, float[12] value) {
        if (render_state.vertex_config.tex_configs[config_idx].tex_matrix != value) {
            flush();
            render_state.vertex_config.tex_configs[config_idx].tex_matrix = value;
        }
    }
    
    void set_tex_config_normalize_before_dualtex(int config_idx, GLBool value) {
        if (render_state.vertex_config.tex_configs[config_idx].normalize_before_dualtex != value) {
            flush();
            render_state.vertex_config.tex_configs[config_idx].normalize_before_dualtex = value;
        }
    }
    
    void set_tex_config_texcoord_source(int config_idx, u32 value) {
        if (render_state.vertex_config.tex_configs[config_idx].texcoord_source != value) {
            flush();
            render_state.vertex_config.tex_configs[config_idx].texcoord_source = value;
        }
    }
    
    void set_tex_config_texmatrix_size(int config_idx, u32 value) {
        if (render_state.vertex_config.tex_configs[config_idx].texmatrix_size != value) {
            flush();
            render_state.vertex_config.tex_configs[config_idx].texmatrix_size = value;
        }
    }
    
    void set_tex_config_use_stq(int config_idx, u32 value) {
        if (render_state.vertex_config.tex_configs[config_idx].use_stq != value) {
            flush();
            render_state.vertex_config.tex_configs[config_idx].use_stq = value;
        }
    }
    
    // TevConfig direct field setters
    void set_tev_num_stages(int value) {
        if (render_state.tev_config.num_tev_stages != value) {
            flush();
            render_state.tev_config.num_tev_stages = value;
        }
    }
    
    void set_tev_swap_tables(u64 value) {
        if (render_state.tev_config.swap_tables != value) {
            flush();
            render_state.tev_config.swap_tables = value;
        }
    }
    
    void set_tev_alpha_comp0(int value) {
        if (render_state.tev_config.alpha_comp0 != value) {
            flush();
            render_state.tev_config.alpha_comp0 = value;
        }
    }
    
    void set_tev_alpha_comp1(int value) {
        if (render_state.tev_config.alpha_comp1 != value) {
            flush();
            render_state.tev_config.alpha_comp1 = value;
        }
    }
    
    void set_tev_alpha_aop(int value) {
        if (render_state.tev_config.alpha_aop != value) {
            flush();
            render_state.tev_config.alpha_aop = value;
        }
    }
    
    void set_tev_alpha_ref0(int value) {
        if (render_state.tev_config.alpha_ref0 != value) {
            flush();
            render_state.tev_config.alpha_ref0 = value;
        }
    }
    
    void set_tev_alpha_ref1(int value) {
        if (render_state.tev_config.alpha_ref1 != value) {
            flush();
            render_state.tev_config.alpha_ref1 = value;
        }
    }
    
    // TevConfig register array setters
    void set_tev_reg(int reg_idx, int component_idx, float value) {
        final switch (reg_idx) {
            case 0:
                if (render_state.tev_config.reg0[component_idx] != value) {
                    flush();
                    render_state.tev_config.reg0[component_idx] = value;
                }
                break;
            case 1:
                if (render_state.tev_config.reg1[component_idx] != value) {
                    flush();
                    render_state.tev_config.reg1[component_idx] = value;
                }
                break;
            case 2:
                if (render_state.tev_config.reg2[component_idx] != value) {
                    flush();
                    render_state.tev_config.reg2[component_idx] = value;
                }
                break;
            case 3:
                if (render_state.tev_config.reg3[component_idx] != value) {
                    flush();
                    render_state.tev_config.reg3[component_idx] = value;
                }
                break;
        }
    }
    
    void set_tev_k(int k_idx, int component_idx, float value) {
        final switch (k_idx) {
            case 0:
                if (render_state.tev_config.k0[component_idx] != value) {
                    flush();
                    render_state.tev_config.k0[component_idx] = value;
                }
                break;
            case 1:
                if (render_state.tev_config.k1[component_idx] != value) {
                    flush();
                    render_state.tev_config.k1[component_idx] = value;
                }
                break;
            case 2:
                if (render_state.tev_config.k2[component_idx] != value) {
                    flush();
                    render_state.tev_config.k2[component_idx] = value;
                }
                break;
            case 3:
                if (render_state.tev_config.k3[component_idx] != value) {
                    flush();
                    render_state.tev_config.k3[component_idx] = value;
                }
                break;
        }
    }
    
    // TevStage setters (for stages 0-15)
    void set_tev_stage_in_color_a(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_color_a != value) {
            flush();
            render_state.tev_config.stages[stage].in_color_a = value;
        }
    }
    
    void set_tev_stage_in_color_b(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_color_b != value) {
            flush();
            render_state.tev_config.stages[stage].in_color_b = value;
        }
    }
    
    void set_tev_stage_in_color_c(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_color_c != value) {
            flush();
            render_state.tev_config.stages[stage].in_color_c = value;
        }
    }
    
    void set_tev_stage_in_color_d(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_color_d != value) {
            flush();
            render_state.tev_config.stages[stage].in_color_d = value;
        }
    }
    
    void set_tev_stage_color_op(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].color_op != value) {
            flush();
            render_state.tev_config.stages[stage].color_op = value;
        }
    }
    
    void set_tev_stage_in_alfa_a(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_alfa_a != value) {
            flush();
            render_state.tev_config.stages[stage].in_alfa_a = value;
        }
    }
    
    void set_tev_stage_in_alfa_b(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_alfa_b != value) {
            flush();
            render_state.tev_config.stages[stage].in_alfa_b = value;
        }
    }
    
    void set_tev_stage_in_alfa_c(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_alfa_c != value) {
            flush();
            render_state.tev_config.stages[stage].in_alfa_c = value;
        }
    }
    
    void set_tev_stage_in_alfa_d(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].in_alfa_d != value) {
            flush();
            render_state.tev_config.stages[stage].in_alfa_d = value;
        }
    }
    
    void set_tev_stage_alfa_op(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].alfa_op != value) {
            flush();
            render_state.tev_config.stages[stage].alfa_op = value;
        }
    }
    
    void set_tev_stage_color_dest(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].color_dest != value) {
            flush();
            render_state.tev_config.stages[stage].color_dest = value;
        }
    }
    
    void set_tev_stage_alfa_dest(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].alfa_dest != value) {
            flush();
            render_state.tev_config.stages[stage].alfa_dest = value;
        }
    }
    
    void set_tev_stage_bias_color(int stage, float value) {
        if (render_state.tev_config.stages[stage].bias_color != value) {
            flush();
            render_state.tev_config.stages[stage].bias_color = value;
        }
    }
    
    void set_tev_stage_scale_color(int stage, float value) {
        if (render_state.tev_config.stages[stage].scale_color != value) {
            flush();
            render_state.tev_config.stages[stage].scale_color = value;
        }
    }
    
    void set_tev_stage_bias_alfa(int stage, float value) {
        if (render_state.tev_config.stages[stage].bias_alfa != value) {
            flush();
            render_state.tev_config.stages[stage].bias_alfa = value;
        }
    }
    
    void set_tev_stage_scale_alfa(int stage, float value) {
        if (render_state.tev_config.stages[stage].scale_alfa != value) {
            flush();
            render_state.tev_config.stages[stage].scale_alfa = value;
        }
    }
    
    void set_tev_stage_ras_channel_id(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].ras_channel_id != value) {
            flush();
            render_state.tev_config.stages[stage].ras_channel_id = value;
        }
    }
    
    void set_tev_stage_ras_swap_table_index(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].ras_swap_table_index != value) {
            flush();
            render_state.tev_config.stages[stage].ras_swap_table_index = value;
        }
    }
    
    void set_tev_stage_tex_swap_table_index(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].tex_swap_table_index != value) {
            flush();
            render_state.tev_config.stages[stage].tex_swap_table_index = value;
        }
    }
    
    void set_tev_stage_texmap(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].texmap != value) {
            flush();
            render_state.tev_config.stages[stage].texmap = value;
        }
    }
    
    void set_tev_stage_texcoord(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].texcoord != value) {
            flush();
            render_state.tev_config.stages[stage].texcoord = value;
        }
    }
    
    void set_tev_stage_texmap_enable(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].texmap_enable != value) {
            flush();
            render_state.tev_config.stages[stage].texmap_enable = value;
        }
    }
    
    void set_tev_stage_clamp_color(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].clamp_color != value) {
            flush();
            render_state.tev_config.stages[stage].clamp_color = value;
        }
    }
    
    void set_tev_stage_clamp_alfa(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].clamp_alfa != value) {
            flush();
            render_state.tev_config.stages[stage].clamp_alfa = value;
        }
    }
    
    void set_tev_stage_kcsel(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].kcsel != value) {
            flush();
            render_state.tev_config.stages[stage].kcsel = value;
        }
    }
    
    void set_tev_stage_kasel(int stage, u32 value) {
        if (render_state.tev_config.stages[stage].kasel != value) {
            flush();
            render_state.tev_config.stages[stage].kasel = value;
        }
    }
    
    // VertexConfig setters
    void set_vertex_config_end(int value) {
        if (render_state.vertex_config.end != value) {
            flush();
            render_state.vertex_config.end = value;
        }
    }
    
    
    // TextureDescriptor setters (for texture_descriptors[0-7])
    void set_texture_descriptor_width(int desc_idx, size_t value) {
        if (render_state.texture_descriptors[desc_idx].width != value) {
            flush();
            render_state.texture_descriptors[desc_idx].width = value;
        }
    }
    
    void set_texture_descriptor_height(int desc_idx, size_t value) {
        if (render_state.texture_descriptors[desc_idx].height != value) {
            flush();
            render_state.texture_descriptors[desc_idx].height = value;
        }
    }
    
    void set_texture_descriptor_type(int desc_idx, TextureType value) {
        if (render_state.texture_descriptors[desc_idx].type != value) {
            flush();
            render_state.texture_descriptors[desc_idx].type = value;
        }
    }
    
    void set_texture_descriptor_base_address(int desc_idx, u32 value) {
        if (render_state.texture_descriptors[desc_idx].base_address != value) {
            flush();
            render_state.texture_descriptors[desc_idx].base_address = value;
        }
    }
    
    void set_texture_descriptor_texture(int desc_idx, Color* value) {
        if (render_state.texture_descriptors[desc_idx].texture != value) {
            flush();
            render_state.texture_descriptors[desc_idx].texture = value;
        }
    }
    
    void set_texture_descriptor_wrap_s(int desc_idx, TextureWrap value) {
        if (render_state.texture_descriptors[desc_idx].wrap_s != value) {
            flush();
            render_state.texture_descriptors[desc_idx].wrap_s = value;
        }
    }
    
    void set_texture_descriptor_wrap_t(int desc_idx, TextureWrap value) {
        if (render_state.texture_descriptors[desc_idx].wrap_t != value) {
            flush();
            render_state.texture_descriptors[desc_idx].wrap_t = value;
        }
    }
    
    void set_texture_descriptor_texcoord_source(int desc_idx, TexcoordSource value) {
        if (render_state.texture_descriptors[desc_idx].texcoord_source != value) {
            flush();
            render_state.texture_descriptors[desc_idx].texcoord_source = value;
        }
    }
    
    void set_texture_descriptor_dualtex_matrix_slot(int desc_idx, int value) {
        if (render_state.texture_descriptors[desc_idx].dualtex_matrix_slot != value) {
            flush();
            render_state.texture_descriptors[desc_idx].dualtex_matrix_slot = value;
        }
    }
    
    void set_texture_descriptor_normalize_before_dualtex(int desc_idx, bool value) {
        if (render_state.texture_descriptors[desc_idx].normalize_before_dualtex != value) {
            flush();
            render_state.texture_descriptors[desc_idx].normalize_before_dualtex = value;
        }
    }
    
    void set_texture_descriptor_tex_matrix_slot(int desc_idx, int value) {
        if (render_state.texture_descriptors[desc_idx].tex_matrix_slot != value) {
            flush();
            render_state.texture_descriptors[desc_idx].tex_matrix_slot = value;
        }
    }
    
    void set_texture_descriptor_texmatrix_size(int desc_idx, int value) {
        if (render_state.texture_descriptors[desc_idx].texmatrix_size != value) {
            flush();
            render_state.texture_descriptors[desc_idx].texmatrix_size = value;
        }
    }
    
    void set_texture_descriptor_use_stq(int desc_idx, int value) {
        if (render_state.texture_descriptors[desc_idx].use_stq != value) {
            flush();
            render_state.texture_descriptors[desc_idx].use_stq = value;
        }
    }
    
    void init_opengl() {
        int uniform_buffer_alignment;
        glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, &uniform_buffer_alignment);

        glGenBuffers(1, &persistent_vertex_buffer);
        glBindBuffer(GL_ARRAY_BUFFER, persistent_vertex_buffer);
        glBufferStorage(GL_ARRAY_BUFFER, MAX_VERTICES * Vertex.sizeof, null, 
                       GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        persistent_vertex_ptr = cast(Vertex*) glMapBufferRange(GL_ARRAY_BUFFER, 0, MAX_VERTICES * Vertex.sizeof,
                                                              GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        
        glGenBuffers(1, &persistent_tev_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
        glBufferData(GL_UNIFORM_BUFFER, TevConfig.sizeof, null, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &persistent_vertex_config_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferData(GL_UNIFORM_BUFFER, VertexConfig.sizeof, null, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &persistent_index_buffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, persistent_index_buffer);
        glBufferStorage(GL_ELEMENT_ARRAY_BUFFER, MAX_INDICES * uint.sizeof, null,
                       GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
        persistent_index_ptr = cast(uint*) glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, 0, MAX_INDICES * uint.sizeof,
                                                           GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);

        load_shaders();

        render_state.projection_matrix[15] = 1;
        
        glGenFramebuffers(1, &efb_fbo);
        glGenTextures(1, &efb_color_texture);
        glGenTextures(1, &efb_depth_texture);
        
        glBindTexture(GL_TEXTURE_2D, efb_color_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 528, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glBindTexture(GL_TEXTURE_2D, efb_depth_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, 640, 528, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, efb_color_texture, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, efb_depth_texture, 0);
        
        glGenFramebuffers(1, &xfb_fbo);
        glGenTextures(1, &xfb_color_texture);
        
        glBindTexture(GL_TEXTURE_2D, xfb_color_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 480, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glBindFramebuffer(GL_FRAMEBUFFER, xfb_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, xfb_color_texture, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        
        init_xfb_shader();
    }
    
    private void init_xfb_shader() {
        string xfb_vertex_text = readText("source/emu/hw/hollywood/shaders/xfb_vertex.glsl");
        string xfb_fragment_text = readText("source/emu/hw/hollywood/shaders/xfb_fragment.glsl");
        
        GLuint xfb_vertex_shader = glCreateShader(GL_VERTEX_SHADER);
        auto xfb_vertex_src_ptr = xfb_vertex_text.ptr;
        auto xfb_vertex_src_len = cast(int)xfb_vertex_text.length;
        glShaderSource(xfb_vertex_shader, 1, &xfb_vertex_src_ptr, &xfb_vertex_src_len);
        glCompileShader(xfb_vertex_shader);
        
        GLuint xfb_fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
        auto xfb_fragment_src_ptr = xfb_fragment_text.ptr;
        auto xfb_fragment_src_len = cast(int)xfb_fragment_text.length;
        glShaderSource(xfb_fragment_shader, 1, &xfb_fragment_src_ptr, &xfb_fragment_src_len);
        glCompileShader(xfb_fragment_shader);
        
        xfb_shader_program = glCreateProgram();
        glAttachShader(xfb_shader_program, xfb_vertex_shader);
        glAttachShader(xfb_shader_program, xfb_fragment_shader);
        glLinkProgram(xfb_shader_program);
        
        glDeleteShader(xfb_vertex_shader);
        glDeleteShader(xfb_fragment_shader);
        
        float[] xfb_quad_vertices = [
            -1.0f, -1.0f,  0.0f, 1.0f,
             1.0f, -1.0f,  1.0f, 1.0f,
             1.0f,  1.0f,  1.0f, 0.0f,
            -1.0f, -1.0f,  0.0f, 1.0f,
             1.0f,  1.0f,  1.0f, 0.0f,
            -1.0f,  1.0f,  0.0f, 0.0f
        ];
        
        glGenVertexArrays(1, &xfb_vao);
        glGenBuffers(1, &xfb_vbo);
        
        glBindVertexArray(xfb_vao);
        glBindBuffer(GL_ARRAY_BUFFER, xfb_vbo);
        glBufferData(GL_ARRAY_BUFFER, xfb_quad_vertices.length * float.sizeof, xfb_quad_vertices.ptr, GL_STATIC_DRAW);
        
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)0);
        glEnableVertexAttribArray(0);
        
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)(2 * float.sizeof));
        glEnableVertexAttribArray(1);
        
        glBindVertexArray(0);
    }
    
    private void load_shaders() {
        auto vertex_shader   = glCreateShader(GL_VERTEX_SHADER);
        auto fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);	
        string vertex_text   = readText("source/emu/hw/hollywood/shaders/vertex.glsl");
        string fragment_text = readText("source/emu/hw/hollywood/shaders/fragment.glsl");

        auto vertex_src_ptr = vertex_text.ptr;
        auto vertex_src_len = cast(int)vertex_text.length;
        glShaderSource(vertex_shader, 1, &vertex_src_ptr, &vertex_src_len);
        glCompileShader(vertex_shader);

        auto fragment_src_ptr = fragment_text.ptr;
        auto fragment_src_len = cast(int)fragment_text.length;
        glShaderSource(fragment_shader, 1, &fragment_src_ptr, &fragment_src_len);
        glCompileShader(fragment_shader);

        gl_program = glCreateProgram();
        glAttachShader(gl_program, vertex_shader);
        glAttachShader(gl_program, fragment_shader);
        glLinkProgram(gl_program);

        position_attr_location           = glGetAttribLocation(gl_program,  "in_Position");
        normal_attr_location             = glGetAttribLocation(gl_program,  "normal");
        texcoord_attr_location           = glGetAttribLocation(gl_program,  "texcoord");
        color_attr_location              = glGetAttribLocation(gl_program,  "in_color");
        matrix_index_attr_location       = glGetAttribLocation(gl_program,  "matrix_index");
        position_matrix_uniform_location = glGetUniformLocation(gl_program, "position_matrix");
        texture_matrix_uniform_location  = glGetUniformLocation(gl_program, "texture_matrix");
        matrix_data_uniform_location     = glGetUniformLocation(gl_program, "matrix_data");
        mvp_uniform_location             = glGetUniformLocation(gl_program, "MVP");
        tev_config_block_index           = glGetUniformBlockIndex(gl_program, "TevConfig");
        vertex_config_block_index        = glGetUniformBlockIndex(gl_program, "VertexConfig");

        for (int i = 0; i < 8; i++) {
            import std.string;
            auto texture_name = format("wiiscreen%d", i);
            texture_uniform_locations[i] = glGetUniformLocation(gl_program, texture_name.ptr);
        }

        glDeleteShader(vertex_shader);
        glDeleteShader(fragment_shader);
    }
    
    
    void set_general_matrix_ram(float[256] matrix_ram) {
        general_matrix_ram = matrix_ram;
    }
    
    GLuint get_efb_fbo() const { return efb_fbo; }
    GLuint get_xfb_fbo() const { return xfb_fbo; }
    GLuint get_xfb_color_texture() const { return xfb_color_texture; }
    GLuint get_xfb_shader_program() const { return xfb_shader_program; }
    GLuint get_xfb_vao() const { return xfb_vao; }
    
    uint get_current_vertex_offset() const { return current_vertex_offset; }
    uint get_current_index_offset() const { return current_index_offset; }
    void set_current_vertex_offset(uint offset) { current_vertex_offset = offset; }
    void set_current_index_offset(uint offset) { current_index_offset = offset; }
    
    private uint current_vertex_offset = 0;
    private uint current_index_offset = 0;
    
    private bool xfb_has_data = false;
    
    Vertex* allocate_vertex() {
        if (current_vertex_offset >= MAX_VERTICES) {
            current_vertex_offset = 0;
        }
        
        return &persistent_vertex_ptr[current_vertex_offset++];
    }
    
    uint* allocate_index() {
        if (current_index_offset >= MAX_INDICES) {
            current_index_offset = 0;
        }
        
        return &persistent_index_ptr[current_index_offset++];
    }
    
    private uint gc_blend_factor_to_gl(int gc_factor) {
        final switch (gc_factor) {
            case 0: return GL_ZERO;
            case 1: return GL_ONE;
            case 2: return GL_SRC_COLOR;
            case 3: return GL_ONE_MINUS_SRC_COLOR;
            case 4: return GL_SRC_ALPHA;
            case 5: return GL_ONE_MINUS_SRC_ALPHA;
            case 6: return GL_DST_ALPHA;
            case 7: return GL_ONE_MINUS_DST_ALPHA;
        }
    }
    
    void apply_opengl_state(RenderState render_state) {
        glUseProgram(gl_program);

        glClearColor(
            render_state.clear_color_red / 255.0f,
            render_state.clear_color_green / 255.0f,
            render_state.clear_color_blue / 255.0f,
            render_state.clear_color_alpha / 255.0f
        ); 
        
        gl_object_manager.deallocate_all_objects();
        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE, render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv(mvp_uniform_location, 1, GL_FALSE, render_state.projection_matrix.ptr);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);

        import std.stdio; writefln("num tev stages: %d", render_state.tev_config.num_tev_stages);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, TevConfig.sizeof, &render_state.tev_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_tev_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, VertexConfig.sizeof, &render_state.vertex_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_vertex_config_buffer);

        if (render_state.arithmetic_blending_enable) {
            glEnable(GL_BLEND);

            auto op1 = gc_blend_factor_to_gl(render_state.blend_source);
            auto op2 = gc_blend_factor_to_gl(render_state.blend_destination);
            glBlendFunc(op1, op2);
        } else {
            glDisable(GL_BLEND);
        }

        while (render_state.enabled_textures_bitmap != 0) {
            int i = cast(int) render_state.enabled_textures_bitmap.bfs;
            render_state.enabled_textures_bitmap &= ~(1 << i);

            glActiveTexture(GL_TEXTURE0 + i);
            glBindTexture(GL_TEXTURE_2D, render_state.texture[i].texture_id);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

            final switch (render_state.texture[i].wrap_s) {
                case TextureWrap.Clamp:
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                    break;
                
                case TextureWrap.Repeat:
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
                    break;
                
                case TextureWrap.Mirror:
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_MIRRORED_REPEAT);
                    break;
            }

            final switch (render_state.texture[i].wrap_t) {
                case TextureWrap.Clamp:
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                    break;
                
                case TextureWrap.Repeat:
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
                    break;
                
                case TextureWrap.Mirror:
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_MIRRORED_REPEAT);
                    break;
            }

            glUniform1i(texture_uniform_locations[i], i);
        }

        glColorMask(
            render_state.color_update_enable, 
            render_state.color_update_enable, 
            render_state.color_update_enable, 
            render_state.alpha_update_enable
        );

        if (render_state.depth_test_enabled) {
            glEnable(GL_DEPTH_TEST);
            glDepthFunc(render_state.depth_func);
        } else {
            glDisable(GL_DEPTH_TEST);
        }

        glDepthMask(render_state.depth_write_enabled ? GL_TRUE : GL_FALSE);

        final switch (render_state.cull_mode) {
            case 0:
                // glDisable(GL_CULL_FACE);
                break;
            case 1:
                // glEnable(GL_CULL_FACE);
                // glCullFace(GL_FRONT);
                break;
            case 2:
                // glEnable(GL_CULL_FACE);
                // glCullFace(GL_BACK);
                break;
        }
    }
    
    void submit_geometry_to_opengl(ShapeGroup geometry, RenderState render_state) {
        uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
        glBindVertexArray(vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, persistent_vertex_buffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, persistent_index_buffer);
        size_t base_offset = geometry.shared_vertex_start * Vertex.sizeof;
        
        glEnableVertexAttribArray(position_attr_location);
        glVertexAttribPointer(position_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 0));
        glEnableVertexAttribArray(normal_attr_location);
        glVertexAttribPointer(normal_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 3 * float.sizeof));
        glEnableVertexAttribArray(texcoord_attr_location);
        glVertexAttribPointer(texcoord_attr_location, 2, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 6 * float.sizeof));
        glEnableVertexAttribArray(color_attr_location);
        glVertexAttribPointer(color_attr_location, 4, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 22 * float.sizeof));
        glEnableVertexAttribArray(matrix_index_attr_location);
        glVertexAttribIPointer(matrix_index_attr_location, 1, GL_INT, Vertex.sizeof, cast(void*) (base_offset + 30 * float.sizeof));
            
        if (render_state.uses_per_vertex_matrices) {
            glUniform1fv(matrix_data_uniform_location, 256, general_matrix_ram.ptr);
        } else {
            glUniformMatrix4x3fv(position_matrix_uniform_location, 1, GL_TRUE, render_state.position_matrix.ptr);
        }

        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE,  render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv  (mvp_uniform_location,            1, GL_FALSE, render_state.projection_matrix.ptr);
        glUniformBlockBinding(gl_program, tev_config_block_index, 1);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_tev_buffer);
        glUniformBlockBinding(gl_program, vertex_config_block_index, 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_vertex_config_buffer);
        glDrawElements(GL_TRIANGLES, cast(int) geometry.shared_index_count, GL_UNSIGNED_INT,
                       cast(void*) (geometry.shared_index_start * uint.sizeof));
    }
    
    void flush_and_render(T)(T geometry) {
        ShapeGroup converted_geometry;
        converted_geometry.shared_vertex_start = geometry.shared_vertex_start;
        converted_geometry.shared_vertex_count = geometry.shared_vertex_count;
        converted_geometry.shared_index_start  = geometry.shared_index_start;
        converted_geometry.shared_index_count  = geometry.shared_index_count;
        
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        
        apply_opengl_state(render_state);
        submit_geometry_to_opengl(converted_geometry, render_state);
    }
    
    void debug_draw_texture(Texture texture, int x, int y, int w, int h) {
    }
    
    void efb_copy_to_xfb() {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, efb_fbo);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, xfb_fbo);

        glColorMask(true, true, true, true);
        glBlitFramebuffer(render_state.efb_src_x, render_state.efb_src_y, render_state.efb_src_x + render_state.efb_src_w, render_state.efb_src_y + render_state.efb_src_h, render_state.efb_src_x, render_state.efb_src_y, render_state.efb_src_x + render_state.efb_src_w, render_state.efb_src_y + render_state.efb_src_h, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        xfb_has_data = true;
    }
    
    void efb_copy_to_texture(u8* buffer) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, efb_fbo);
        glReadPixels(render_state.efb_src_x, render_state.efb_src_y, render_state.efb_src_w, render_state.efb_src_h, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    }
    
    void clear_efb() {
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        glClearColor(
            render_state.clear_color_red / 255.0f,
            render_state.clear_color_green / 255.0f,
            render_state.clear_color_blue / 255.0f,
            render_state.clear_color_alpha / 255.0f
        );
        glClearDepth((render_state.clear_depth & 0xFFFFFF) / 16777215.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    }
    
    void update_gl_viewport(int gl_x, int gl_y, int gl_width, int gl_height) {
        glViewport(gl_x, gl_y, gl_width, gl_height);
    }
    
    void render_xfb() {
        if (xfb_has_data) {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glDisable(GL_DEPTH_TEST);
            glDisable(GL_BLEND);
            glDisable(GL_SCISSOR_TEST);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, xfb_color_texture);
            glUseProgram(xfb_shader_program);
            glUniform1i(glGetUniformLocation(xfb_shader_program, "u_texture"), 0);
            glBindVertexArray(xfb_vao);
            glDrawArrays(GL_TRIANGLES, 0, 6);
            glBindVertexArray(0);
        }
    }
}