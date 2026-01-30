module emu.hw.hollywood.opengl.opengl_renderer;

import bindbc.opengl;
import config;
import emu.hw.hollywood.opengl.efb;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.texture;
import util.bitop;
import util.log;
import util.number;
import std.algorithm;
import std.file;
import std.format;
import std.stdio;
import std.string;
import std.math;

alias GLBool = u32;

struct BufferWaitStats {
    size_t total_waits;
    size_t[] per_segment;
}

template SegmentedPersistentBuffer(T) {
    final class SegmentedPersistentBuffer {
        private {
            GLuint buffer = 0;
            T* mapped_ptr = null;
            size_t element_count;
            size_t segment_count;
            size_t segment_size; // in elements
            size_t current_segment = 0;
            size_t used_in_segment = 0;
            GLsync[] fences;
            GLenum target;
            string debug_name;
            BufferWaitStats wait_stats;
        }

        this(GLenum target, size_t element_count, size_t segment_count, string debug_name) {
            this.target = target;
            this.element_count = element_count;
            this.segment_count = segment_count;
            this.segment_size = element_count / segment_count;
            this.debug_name = debug_name;
            fences.length = segment_count;
            fences[] = null;
            
            static if (config_enable_opengl_buffer_wait_stats) {
                wait_stats.per_segment.length = segment_count;
                wait_stats.per_segment[] = 0;
                wait_stats.total_waits = 0;
            }

            glGenBuffers(1, &buffer);
            glBindBuffer(target, buffer);
            glBufferStorage(target, element_count * T.sizeof, null,
                            GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
            mapped_ptr = cast(T*) glMapBufferRange(target, 0, element_count * T.sizeof,
                                                  GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT);
            static if (config_enable_opengl_buffer_wait_stats) {
                writefln("SegmentedPersistentBuffer created: name=%s target=0x%x elements=%d segment_count=%d segment_size=%d total_bytes=%d",
                         debug_name, target, element_count, segment_count, segment_size, element_count * T.sizeof);
            }
        }

        T* acquire(size_t count) {
            if (count > segment_size) {
                error_opengl("SegmentedPersistentBuffer request too large: %d > segment_size %d", count, segment_size);
            }

            if (fences[current_segment] !is null && used_in_segment == 0) {
                glClientWaitSync(fences[current_segment], GL_SYNC_FLUSH_COMMANDS_BIT, GLuint.max);
                glDeleteSync(fences[current_segment]);
                fences[current_segment] = null;
                
                static if (config_enable_opengl_buffer_wait_stats) {
                    record_wait_for_segment(current_segment);
                }
            }

            if (used_in_segment + count > segment_size) {
                advance_segment();
            }

            size_t offset = (current_segment * segment_size) + used_in_segment;
            used_in_segment += count;
            return mapped_ptr + offset;
        }

        size_t get_current_offset() const {
            return (current_segment * segment_size) + used_in_segment;
        }

        size_t get_segment_size() const {
            return segment_size;
        }

        void mark_segment_submitted() {
            if (used_in_segment == 0) {
                return;
            }

            if (fences[current_segment] !is null) {
                glDeleteSync(fences[current_segment]);
            }

            fences[current_segment] = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
        }

        GLuint get_buffer() const {
            return buffer;
        }

        string get_debug_name() const {
            return debug_name;
        }

        BufferWaitStats consume_wait_stats() {
            static if (!config_enable_opengl_buffer_wait_stats) {
                assert(0, "consume_wait_stats called while config_enable_opengl_buffer_wait_stats is false");
            }
            
            BufferWaitStats result;
            result.total_waits = wait_stats.total_waits;
            result.per_segment = wait_stats.per_segment.dup;
            wait_stats.total_waits = 0;
            wait_stats.per_segment[] = 0;
            return result;
        }

        private void advance_segment() {
            mark_segment_submitted();
            size_t next_segment = (current_segment + 1) % segment_count;

            if (fences[next_segment] !is null) {
                glClientWaitSync(fences[next_segment], GL_SYNC_FLUSH_COMMANDS_BIT, GLuint.max);
                glDeleteSync(fences[next_segment]);
                fences[next_segment] = null;
                static if (config_enable_opengl_buffer_wait_stats) {
                    record_wait_for_segment(next_segment);
                }
            }

            current_segment = next_segment;
            used_in_segment = 0;
        }

        private void record_wait_for_segment(size_t segment) {
            if (segment < wait_stats.per_segment.length) {
                wait_stats.per_segment[segment] += 1;
            }
            wait_stats.total_waits += 1;
        }
    }
}

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

        int forced_alpha;
        int is_alpha_forced;

        float zbias;
        int ztexture_fmt;
        int ztexture_op;
    }

    struct TexConfig {
        align(1):
        float[12] tex_matrix;
        float[12] dualtex_matrix;
        GLBool    normalize_before_dualtex;
        u32       texcoord_source;
        u32       texmatrix_size;
        u32       use_stq;
    }

    struct ChannelControl {
        align(1):
        GLBool enable;
        u32    ambient_src;
        u32    material_src;
        u32    light_mask;
        u32    diffuse_fn;
        u32    attenuation_fn;
        u32[2] padding;
    }

    struct Light {
        align(1):
        float[4] position;
        float[4] direction;
        float[4] color;
        float[4] dist_atten;
        float[4] spec_atten;
    }

    struct VertexConfig {
        align(1):
        TexConfig[8] tex_configs;
        ChannelControl[2] color_channel_controls;
        ChannelControl[2] alpha_channel_controls;
        Light[8] lights;
        float[4][2] ambient_colors;
        float[4][2] material_colors;
        int end;
        int[3] padding_end;
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
        u8 min_filter;
        u8 mag_filter;
        float min_lod;
        float max_lod;
        float lod_bias;
        bool edge_lod;
        bool bias_clamp;
        u8 max_aniso;
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
        bool logicop_enable;
        int logicop;
        
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

        int viewport_width;
        int viewport_height;
        int viewport_x;
        int viewport_y;
        float viewport_near;
        float viewport_far;

        int scissor_top;
        int scissor_bottom;
        int scissor_left;
        int scissor_right;
        int scissorbox_offset_x;
        int scissorbox_offset_y;
    }

    private RenderState render_state;
    private ShapeGroup accumulated_geometry;
    
    private GlObjectManager gl_object_manager;
    private EFBCopyOptimizer efb_optimizer;
    private SegmentedPersistentBuffer!Vertex vertex_buffer;
    private SegmentedPersistentBuffer!uint   index_buffer;
    private GLuint persistent_tev_buffer = 0;
    private GLuint persistent_vertex_config_buffer = 0;
    
    private GLuint gl_program;
    private int[8] texture_uniform_locations;
    private int position_attr_location = -1;
    private int normal_attr_location = -1;
    private int binormal_t_attr_location = -1;
    private int binormal_b_attr_location = -1;
    private int texcoord_attr_location = -1;
    private int color_attr_location = -1;
    private int matrix_index_attr_location = -1;
    private int position_matrix_uniform_location = -1;
    private int normal_matrix_uniform_location = -1;
    private int texture_matrix_uniform_location = -1;
    private int matrix_data_uniform_location = -1;
    private int normal_matrix_data_uniform_location = -1;
    private int mvp_uniform_location = -1;
    private uint tev_config_block_index = -1;
    private uint vertex_config_block_index = -1;
    private float[256] general_matrix_ram;
    private float[256] normal_matrix_ram;
    
    private GLuint efb_fbo;
    private GLuint efb_color_texture;
    private GLuint efb_depth_texture;
    private GLuint xfb_fbo;
    private GLuint xfb_color_texture;
    private GLuint xfb_shader_program;
    private GLuint xfb_vao;
    private GLuint xfb_vbo;
    private u32[] tracked_efb_copy_addresses;
    private size_t efb_copy_count;
    
    private int[] draw_call_vertex_counts;
    
    static immutable size_t MAX_VERTICES = 1024 * 1024;
    static immutable size_t MAX_INDICES = MAX_VERTICES * 6;
    
    this(GlObjectManager gl_object_manager) {
        this.gl_object_manager = gl_object_manager;
        this.efb_optimizer = new EFBCopyOptimizer(gl_object_manager);
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
        return vertex_buffer.acquire(1);
    }

    Vertex* next_vertices(size_t count) {
        return vertex_buffer.acquire(count);
    }
    
    uint* next_index() {
        return index_buffer.acquire(1);
    }

    uint* next_indices(size_t count) {
        return index_buffer.acquire(count);
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
            accumulated_geometry.shared_vertex_start = cast(uint) vertex_buffer.get_current_offset();
            accumulated_geometry.shared_index_start = cast(uint) index_buffer.get_current_offset();
        }
    }
    
    uint get_local_vertex_index() {
        return cast(uint)(vertex_buffer.get_current_offset() - accumulated_geometry.shared_vertex_start);
    }
    
    void finalize_geometry() {
        accumulated_geometry.shared_index_count = cast(uint)(index_buffer.get_current_offset() - accumulated_geometry.shared_index_start);
        accumulated_geometry.shared_vertex_count = cast(uint)(vertex_buffer.get_current_offset() - accumulated_geometry.shared_vertex_start);
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

    void set_normal_matrix(float[12] value) {
        if (render_state.normal_matrix != value) {
            flush();
            render_state.normal_matrix = value;
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

    void set_scissor_top(int value) {
        if (render_state.scissor_top != value) {
            flush();
            render_state.scissor_top = value;
        }
    }

    void set_scissor_bottom(int value) {
        if (render_state.scissor_bottom != value) {
            flush();
            render_state.scissor_bottom = value;
        }
    }

    void set_scissor_left(int value) {
        if (render_state.scissor_left != value) {
            flush();
            render_state.scissor_left = value;
        }
    }

    void set_scissor_right(int value) {
        if (render_state.scissor_right != value) {
            flush();
            render_state.scissor_right = value;
        }
    }

    void set_scissorbox_offset_x(int value) {
        if (render_state.scissorbox_offset_x != value) {
            flush();
            render_state.scissorbox_offset_x = value;
        }
    }

    void set_scissorbox_offset_y(int value) {
        if (render_state.scissorbox_offset_y != value) {
            flush();
            render_state.scissorbox_offset_y = value;
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

    void set_logicop_enable(bool value) {
        if (render_state.logicop_enable != value) {
            flush();
            render_state.logicop_enable = value;
        }
    }

    void set_logicop(u32 value) {
        if (render_state.logicop != value) {
            flush();
            render_state.logicop = value;
        }
    }

    // Texture setters
    void set_texture_id(int tex_idx, int value) {
        if (render_state.texture[tex_idx].texture_id != value) {
            flush();
            render_state.texture[tex_idx].texture_id = value;
        }
    }

    void set_texture_max_level(int tex_idx, int value) {
        if (render_state.texture[tex_idx].max_level != value) {
            flush();
            render_state.texture[tex_idx].max_level = value;
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

    int get_tev_num_stages() {
        return render_state.tev_config.num_tev_stages;
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
    
    void set_forced_alpha(int forced_alpha) {
        if (render_state.tev_config.forced_alpha != forced_alpha) {
            flush();
            render_state.tev_config.forced_alpha = forced_alpha;
        }
    }

    void set_is_alpha_forced(bool is_alpha_forced) {
        if (render_state.tev_config.is_alpha_forced != is_alpha_forced) {
            flush();
            render_state.tev_config.is_alpha_forced = is_alpha_forced;
        }
    }
    
    // VertexConfig setters
    void set_color_channel_control(int idx, ChannelControl value) {
        if (render_state.vertex_config.color_channel_controls[idx] != value) {
            flush();
            render_state.vertex_config.color_channel_controls[idx] = value;
        }
    }

    void set_alpha_channel_control(int idx, ChannelControl value) {
        if (render_state.vertex_config.alpha_channel_controls[idx] != value) {
            flush();
            render_state.vertex_config.alpha_channel_controls[idx] = value;
        }
    }

    void set_light(int idx, Light value) {
        if (render_state.vertex_config.lights[idx] != value) {
            flush();
            render_state.vertex_config.lights[idx] = value;
        }
    }

    void set_ambient_color(int idx, float[4] value) {
        if (render_state.vertex_config.ambient_colors[idx] != value) {
            flush();
            render_state.vertex_config.ambient_colors[idx] = value;
        }
    }

    void set_material_color(int idx, float[4] value) {
        if (render_state.vertex_config.material_colors[idx] != value) {
            flush();
            render_state.vertex_config.material_colors[idx] = value;
        }
    }

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
    
    void set_texture_descriptor_dualtex_matrix_slot(int desc_idx, int value) {
        if (render_state.texture_descriptors[desc_idx].dualtex_matrix_slot != value) {
            flush();
            render_state.texture_descriptors[desc_idx].dualtex_matrix_slot = value;
        }
    }
    
    void set_texture_descriptor_tex_matrix_slot(int desc_idx, int value) {
        if (render_state.texture_descriptors[desc_idx].tex_matrix_slot != value) {
            flush();
            render_state.texture_descriptors[desc_idx].tex_matrix_slot = value;
        }
    }

    void set_texture_descriptor_min_filter(int desc_idx, u8 value) {
        if (render_state.texture_descriptors[desc_idx].min_filter != value) {
            flush();
            render_state.texture_descriptors[desc_idx].min_filter = value;
        }
    }

    void set_texture_descriptor_mag_filter(int desc_idx, u8 value) {
        if (render_state.texture_descriptors[desc_idx].mag_filter != value) {
            flush();
            render_state.texture_descriptors[desc_idx].mag_filter = value;
        }
    }

    void set_texture_descriptor_min_lod(int desc_idx, float value) {
        if (render_state.texture_descriptors[desc_idx].min_lod != value) {
            flush();
            render_state.texture_descriptors[desc_idx].min_lod = value;
        }
    }

    void set_texture_descriptor_max_lod(int desc_idx, float value) {
        if (render_state.texture_descriptors[desc_idx].max_lod != value) {
            flush();
            render_state.texture_descriptors[desc_idx].max_lod = value;
        }
    }

    void set_texture_descriptor_lod_bias(int desc_idx, float value) {
        if (render_state.texture_descriptors[desc_idx].lod_bias != value) {
            flush();
            render_state.texture_descriptors[desc_idx].lod_bias = value;
        }
    }

    void set_texture_descriptor_edge_lod(int desc_idx, bool value) {
        if (render_state.texture_descriptors[desc_idx].edge_lod != value) {
            flush();
            render_state.texture_descriptors[desc_idx].edge_lod = value;
        }
    }

    void set_texture_descriptor_bias_clamp(int desc_idx, bool value) {
        if (render_state.texture_descriptors[desc_idx].bias_clamp != value) {
            flush();
            render_state.texture_descriptors[desc_idx].bias_clamp = value;
        }
    }

    void set_texture_descriptor_max_aniso(int desc_idx, u8 value) {
        if (render_state.texture_descriptors[desc_idx].max_aniso != value) {
            flush();
            render_state.texture_descriptors[desc_idx].max_aniso = value;
        }
    }

    void set_zbias(float value) {
        if (render_state.tev_config.zbias != value) {
            flush();
            render_state.tev_config.zbias = value;
        }
    }

    void set_ztexture_fmt(int value) {
        if (render_state.tev_config.ztexture_fmt != value) {
            flush();
            render_state.tev_config.ztexture_fmt = value;
        }
    }

    void set_ztexture_op(int value) {
        if (render_state.tev_config.ztexture_op != value) {
            flush();
            render_state.tev_config.ztexture_op = value;
        }
    }
    
    void init_opengl() {
        vertex_buffer = new SegmentedPersistentBuffer!Vertex(GL_ARRAY_BUFFER,         MAX_VERTICES, config_opengl_persistent_buffer_segments, "vertex");
        index_buffer  = new SegmentedPersistentBuffer!uint  (GL_ELEMENT_ARRAY_BUFFER, MAX_INDICES,  config_opengl_persistent_buffer_segments, "index");

        glGenBuffers(1, &persistent_tev_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
        glBufferData(GL_UNIFORM_BUFFER, TevConfig.sizeof, null, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &persistent_vertex_config_buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferData(GL_UNIFORM_BUFFER, VertexConfig.sizeof, null, GL_DYNAMIC_DRAW);

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
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 640, 528, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
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
        
        int compiled;

        GLuint xfb_vertex_shader = glCreateShader(GL_VERTEX_SHADER);
        auto xfb_vertex_src_ptr = xfb_vertex_text.ptr;
        auto xfb_vertex_src_len = cast(int)xfb_vertex_text.length;
        glShaderSource(xfb_vertex_shader, 1, &xfb_vertex_src_ptr, &xfb_vertex_src_len);
        glCompileShader(xfb_vertex_shader);
        glGetShaderiv(xfb_vertex_shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled) {
            import core.stdc.stdlib;
            import std.string;
            
            char* info_log = cast(char*) malloc(10000000);
            int info_log_length;

            glGetShaderInfoLog(xfb_vertex_shader, 10000000, &info_log_length, cast(char*) info_log);
            error_hollywood("Vertex shader compilation error: %s", info_log.fromStringz);
        } 
        
        GLuint xfb_fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
        auto xfb_fragment_src_ptr = xfb_fragment_text.ptr;
        auto xfb_fragment_src_len = cast(int)xfb_fragment_text.length;
        glShaderSource(xfb_fragment_shader, 1, &xfb_fragment_src_ptr, &xfb_fragment_src_len);
        glCompileShader(xfb_fragment_shader);
        glGetShaderiv(xfb_fragment_shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled) {
            import core.stdc.stdlib;
            import std.string;
            
            char* info_log = cast(char*) malloc(10000000);
            int info_log_length;

            glGetShaderInfoLog(xfb_fragment_shader, 10000000, &info_log_length, cast(char*) info_log);
            error_hollywood("Vertex shader compilation error in: %s", info_log.fromStringz);
        } 
        
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

        int compiled;

        auto vertex_src_ptr = vertex_text.ptr;
        auto vertex_src_len = cast(int)vertex_text.length;
        glShaderSource(vertex_shader, 1, &vertex_src_ptr, &vertex_src_len);
        glCompileShader(vertex_shader);
        glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled) {
            import core.stdc.stdlib;
            import std.string;
            
            char* info_log = cast(char*) malloc(10000000);
            int info_log_length;

            glGetShaderInfoLog(vertex_shader, 10000000, &info_log_length, cast(char*) info_log);
            error_hollywood("Vertex shader compilation error in: %s", info_log.fromStringz);
        } 

        auto fragment_src_ptr = fragment_text.ptr;
        auto fragment_src_len = cast(int)fragment_text.length;
        glShaderSource(fragment_shader, 1, &fragment_src_ptr, &fragment_src_len);
        glCompileShader(fragment_shader);
        glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled) {
            import core.stdc.stdlib;
            import std.string;
            
            char* info_log = cast(char*) malloc(10000000);
            int info_log_length;

            glGetShaderInfoLog(fragment_shader, 10000000, &info_log_length, cast(char*) info_log);
            error_hollywood("Vertex shader compilation error in: %s", info_log.fromStringz);
        } 

        gl_program = glCreateProgram();
        glAttachShader(gl_program, vertex_shader);
        glAttachShader(gl_program, fragment_shader);
        glLinkProgram(gl_program);

        position_attr_location           = glGetAttribLocation(gl_program,  "in_Position");
        normal_attr_location             = glGetAttribLocation(gl_program,  "normal");
        binormal_t_attr_location         = glGetAttribLocation(gl_program,  "binormal_t");
        binormal_b_attr_location         = glGetAttribLocation(gl_program,  "binormal_b");
        texcoord_attr_location           = glGetAttribLocation(gl_program,  "texcoord");
        color_attr_location              = glGetAttribLocation(gl_program,  "in_color");
        matrix_index_attr_location       = glGetAttribLocation(gl_program,  "matrix_index");
        position_matrix_uniform_location = glGetUniformLocation(gl_program, "position_matrix");
        normal_matrix_uniform_location   = glGetUniformLocation(gl_program, "normal_matrix");
        texture_matrix_uniform_location  = glGetUniformLocation(gl_program, "texture_matrix");
        matrix_data_uniform_location     = glGetUniformLocation(gl_program, "matrix_data");
        normal_matrix_data_uniform_location = glGetUniformLocation(gl_program, "normal_matrix_data");
        mvp_uniform_location             = glGetUniformLocation(gl_program, "MVP");
        tev_config_block_index           = glGetUniformBlockIndex(gl_program, "TevConfig");
        vertex_config_block_index        = glGetUniformBlockIndex(gl_program, "VertexConfig");

        // Sanity-check std140 offsets for VertexConfig against our D layout.
        auto get_uniform_offset = (string name) {
            GLuint idx = glGetProgramResourceIndex(gl_program, GL_UNIFORM, name.ptr);
            assert_opengl(idx != GL_INVALID_INDEX, "Uniform %s not found for offset check", name);

            GLenum prop = GL_OFFSET;
            GLint result;
            glGetProgramResourceiv(gl_program, GL_UNIFORM, idx, 1, &prop, 1, null, &result);
            return result;
        };

        auto assert_offset = (string name, size_t expected) {
            size_t got = cast(size_t) get_uniform_offset(name);
            assert_opengl(got == expected,
                "Uniform offset mismatch for %s: expected %d got %d", name, expected, got);
        };

        VertexConfig vc;
        size_t base = cast(size_t) &vc;

        assert_offset("tex_configs[0].dualtex_matrix",      cast(size_t) &vc.tex_configs[0].dualtex_matrix - base);
        assert_offset("tex_configs[0].tex_matrix",          cast(size_t) &vc.tex_configs[0].tex_matrix - base);
        assert_offset("tex_configs[0].normalize_before_dualtex", cast(size_t) &vc.tex_configs[0].normalize_before_dualtex - base);
        assert_offset("tex_configs[0].texcoord_source",     cast(size_t) &vc.tex_configs[0].texcoord_source - base);
        assert_offset("tex_configs[0].texmatrix_size",      cast(size_t) &vc.tex_configs[0].texmatrix_size - base);

        assert_offset("color_channel_controls[0].enable",         cast(size_t) &vc.color_channel_controls[0].enable - base);
        assert_offset("color_channel_controls[0].ambient_src",    cast(size_t) &vc.color_channel_controls[0].ambient_src - base);
        assert_offset("color_channel_controls[0].material_src",   cast(size_t) &vc.color_channel_controls[0].material_src - base);
        assert_offset("color_channel_controls[0].light_mask",     cast(size_t) &vc.color_channel_controls[0].light_mask - base);
        assert_offset("color_channel_controls[0].diffuse_fn",     cast(size_t) &vc.color_channel_controls[0].diffuse_fn - base);
        assert_offset("color_channel_controls[0].attenuation_fn", cast(size_t) &vc.color_channel_controls[0].attenuation_fn - base);

        assert_offset("alpha_channel_controls[0].enable",         cast(size_t) &vc.alpha_channel_controls[0].enable - base);
        assert_offset("alpha_channel_controls[0].ambient_src",    cast(size_t) &vc.alpha_channel_controls[0].ambient_src - base);
        assert_offset("alpha_channel_controls[0].material_src",   cast(size_t) &vc.alpha_channel_controls[0].material_src - base);
        assert_offset("alpha_channel_controls[0].light_mask",     cast(size_t) &vc.alpha_channel_controls[0].light_mask - base);
        assert_offset("alpha_channel_controls[0].diffuse_fn",     cast(size_t) &vc.alpha_channel_controls[0].diffuse_fn - base);
        assert_offset("alpha_channel_controls[0].attenuation_fn", cast(size_t) &vc.alpha_channel_controls[0].attenuation_fn - base);

        assert_offset("lights[0].position",   cast(size_t) &vc.lights[0].position - base);
        assert_offset("lights[0].direction",  cast(size_t) &vc.lights[0].direction - base);
        assert_offset("lights[0].color",      cast(size_t) &vc.lights[0].color - base);
        assert_offset("lights[0].dist_atten", cast(size_t) &vc.lights[0].dist_atten - base);
        assert_offset("lights[0].spec_atten", cast(size_t) &vc.lights[0].spec_atten - base);

        assert_offset("ambient_colors[0]",  cast(size_t) &vc.ambient_colors[0] - base);
        assert_offset("material_colors[0]", cast(size_t) &vc.material_colors[0] - base);
        assert_offset("end",                cast(size_t) &vc.end - base);

        // cry about it
        texture_uniform_locations = [
            glGetUniformLocation(gl_program, "wiiscreen0"),
            glGetUniformLocation(gl_program, "wiiscreen1"),
            glGetUniformLocation(gl_program, "wiiscreen2"),
            glGetUniformLocation(gl_program, "wiiscreen3"),
            glGetUniformLocation(gl_program, "wiiscreen4"),
            glGetUniformLocation(gl_program, "wiiscreen5"),
            glGetUniformLocation(gl_program, "wiiscreen6"),
            glGetUniformLocation(gl_program, "wiiscreen7"),
        ];

        glDeleteShader(vertex_shader);
        glDeleteShader(fragment_shader);
    }
    
    
    void set_general_matrix_ram(float[256] matrix_ram) {
        general_matrix_ram = matrix_ram;
    }

    void set_normal_matrix_ram(float[256] matrix_ram) {
        normal_matrix_ram = matrix_ram;
    }
    
    GLuint get_efb_fbo() const { return efb_fbo; }
    GLuint get_efb_color_texture() const { return efb_color_texture; }
    
    GLuint copy_efb_to_texture(u8 format, bool mipmap) {
        efb_copy_count++;
        
        apply_opengl_state(render_state);
        return efb_optimizer.copy_efb_to_texture(efb_color_texture, get_efb_src_x(), get_efb_src_y(), get_efb_src_w(), get_efb_src_h(), format, mipmap);
    }
    
    GLuint get_xfb_fbo() const { return xfb_fbo; }
    GLuint get_xfb_color_texture() const { return xfb_color_texture; }
    GLuint get_xfb_shader_program() const { return xfb_shader_program; }
    GLuint get_xfb_vao() const { return xfb_vao; }
    void track_efb_copy(u32 address) {
        tracked_efb_copy_addresses ~= address;
    }

    void clear_tracked_efb_copies() {
        tracked_efb_copy_addresses.length = 0;
    }

    bool is_tracked_efb_address(u32 address) const {
        foreach (a; tracked_efb_copy_addresses) {
            if (a == address) {
                return true;
            }
        }
        
        return false;
    }
    
    private bool xfb_has_data = false;
    
    private uint gc_blend_factor_to_gl(int gc_factor) {
        final switch (gc_factor) {
            case 0: return GL_ZERO;
            case 1: return GL_ONE;
            case 2: return GL_SRC_COLOR;
            case 3: return GL_ONE_MINUS_SRC_COLOR;
            case 4: return GL_SRC1_ALPHA;
            case 5: return GL_ONE_MINUS_SRC1_ALPHA;
            case 6: return GL_DST_ALPHA;
            case 7: return GL_ONE_MINUS_DST_ALPHA;
        }
    }

    private uint gc_logic_op_to_gl(int gc_logic_op) {
        final switch (gc_logic_op) {
            case 0: return GL_CLEAR;
            case 1: return GL_AND;
            case 2: return GL_AND_REVERSE;
            case 3: return GL_COPY;
            case 4: return GL_AND_INVERTED;
            case 5: return GL_NOOP;
            case 6: return GL_XOR;
            case 7: return GL_OR;
            case 8: return GL_NOR;
            case 9: return GL_EQUIV;
            case 10: return GL_INVERT;
            case 11: return GL_OR_REVERSE;
            case 12: return GL_COPY_INVERTED;
            case 13: return GL_OR_INVERTED;
            case 14: return GL_NAND;
            case 15: return GL_SET;
        }
    }

    private uint gx_min_filter_to_gl(u8 min_filter) {
        switch (min_filter) {
            case 0: return GL_NEAREST;
            case 1: return GL_LINEAR;
            case 2: return GL_NEAREST_MIPMAP_NEAREST;
            case 3: return GL_LINEAR_MIPMAP_NEAREST;
            case 4: return GL_NEAREST_MIPMAP_LINEAR;
            case 5: return GL_LINEAR_MIPMAP_LINEAR;
            default: return GL_NEAREST;
        }
    }

    private uint gx_mag_filter_to_gl(u8 mag_filter) {
        return mag_filter == 0 ? GL_NEAREST : GL_LINEAR;
    }

    private float gx_aniso_to_float(u8 max_aniso) {
        switch (max_aniso) {
            case 1: return 2.0f;
            case 2: return 4.0f;
            default: return 1.0f;
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
        
        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE, render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv(mvp_uniform_location, 1, GL_FALSE, render_state.projection_matrix.ptr);

        glBindBuffer(GL_UNIFORM_BUFFER, persistent_tev_buffer);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, TevConfig.sizeof, &render_state.tev_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_tev_buffer);

        glBindBuffer(GL_UNIFORM_BUFFER, persistent_vertex_config_buffer);
        glBufferSubData(GL_UNIFORM_BUFFER, 0, VertexConfig.sizeof, &render_state.vertex_config);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_vertex_config_buffer);

        if (render_state.arithmetic_blending_enable) {
            glEnable(GL_BLEND);
            glDisable(GL_COLOR_LOGIC_OP);

            auto op1 = gc_blend_factor_to_gl(render_state.blend_source);
            auto op2 = gc_blend_factor_to_gl(render_state.blend_destination);

            if (render_state.tev_config.is_alpha_forced) {
                glBlendFuncSeparate(op1, op2, GL_ONE, GL_ZERO);
            } else {
                glBlendFunc(op1, op2);
            }
        } else if (render_state.logicop_enable) {
            glEnable(GL_COLOR_LOGIC_OP);
            glLogicOp(gc_logic_op_to_gl(render_state.logicop));
        } else {
            glEnable(GL_BLEND);
            glDisable(GL_COLOR_LOGIC_OP);
            glBlendFuncSeparate(GL_ONE, GL_ZERO, GL_ONE, GL_ZERO);
        }

        // Unbind all non-enabled texture slots
        for (int i = 0; i < 8; i++) {
            glActiveTexture(GL_TEXTURE0 + i);
            glBindTexture(GL_TEXTURE_2D, 0);
        }


        int enabled = render_state.enabled_textures_bitmap;
        while (enabled != 0) {
            int i = cast(int) enabled.bfs;
            enabled &= ~(1 << i);

            glActiveTexture(GL_TEXTURE0 + i);
            glBindTexture(GL_TEXTURE_2D, render_state.texture[i].texture_id);
            auto desc = render_state.texture_descriptors[i];

            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gx_mag_filter_to_gl(desc.mag_filter));
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gx_min_filter_to_gl(desc.min_filter));
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_LOD, desc.min_lod);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_LOD, desc.max_lod);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_LOD_BIAS, desc.lod_bias);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, max(render_state.texture[i].max_level, 0));
            float aniso = gx_aniso_to_float(desc.max_aniso);
            if (aniso > 1.0f) {
                enum GL_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FE;
                glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, aniso);
            }

            final switch (desc.wrap_t) {
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

            final switch (desc.wrap_s) {
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
            case 3:
                break;
        }

        // the scissor is top-left origin on the wii
        // so we need to convert it to bottom-left origin for opengl
        glEnable(GL_SCISSOR_TEST);
        glScissor(
            render_state.scissor_left + render_state.scissorbox_offset_x,
            528 - render_state.scissor_bottom + render_state.scissorbox_offset_y,
            render_state.scissor_right - render_state.scissor_left,
            render_state.scissor_bottom - render_state.scissor_top
        );

        glViewport(render_state.viewport_x, 528 - render_state.viewport_y - render_state.viewport_height, render_state.viewport_width, render_state.viewport_height);
        glDepthRange(
            1.0, 0.0
        );
        
        glClipControl(GL_LOWER_LEFT, GL_ZERO_TO_ONE);
    }
    
    void submit_geometry_to_opengl(ShapeGroup geometry, RenderState render_state) {
        uint vertex_array_object = gl_object_manager.allocate_vertex_array_object();
        glBindVertexArray(vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer.get_buffer());
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, index_buffer.get_buffer());
        size_t base_offset = geometry.shared_vertex_start * Vertex.sizeof;
        
        glEnableVertexAttribArray(position_attr_location);
        glVertexAttribPointer(position_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 0));
        glEnableVertexAttribArray(normal_attr_location);
        glVertexAttribPointer(normal_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 3 * float.sizeof));
        glEnableVertexAttribArray(binormal_t_attr_location);
        glVertexAttribPointer(binormal_t_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 6 * float.sizeof));
        glEnableVertexAttribArray(binormal_b_attr_location);
        glVertexAttribPointer(binormal_b_attr_location, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 9 * float.sizeof));
        glEnableVertexAttribArray(texcoord_attr_location);
        glVertexAttribPointer(texcoord_attr_location, 2, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 12 * float.sizeof));
        glEnableVertexAttribArray(color_attr_location);
        glVertexAttribPointer(color_attr_location, 4, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*) (base_offset + 28 * float.sizeof));
        glEnableVertexAttribArray(matrix_index_attr_location);
        glVertexAttribIPointer(matrix_index_attr_location, 1, GL_INT, Vertex.sizeof, cast(void*) (base_offset + 36 * float.sizeof));
            
        if (render_state.uses_per_vertex_matrices) {
            glUniform1fv(matrix_data_uniform_location, 256, general_matrix_ram.ptr);
            glUniform1fv(normal_matrix_data_uniform_location, 256, normal_matrix_ram.ptr);
        } else {
            glUniformMatrix4x3fv(position_matrix_uniform_location, 1, GL_TRUE, render_state.position_matrix.ptr);
            glUniformMatrix4x3fv(normal_matrix_uniform_location,   1, GL_TRUE, render_state.normal_matrix.ptr);
        }

        glUniformMatrix4x3fv(texture_matrix_uniform_location, 1, GL_TRUE,  render_state.texture[0].tex_matrix.ptr);
        glUniformMatrix4fv  (mvp_uniform_location,            1, GL_FALSE, render_state.projection_matrix.ptr);
        glUniformBlockBinding(gl_program, tev_config_block_index, 1);
        glBindBufferBase(GL_UNIFORM_BUFFER, 1, persistent_tev_buffer);
        glUniformBlockBinding(gl_program, vertex_config_block_index, 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, persistent_vertex_config_buffer);

        glDrawElements(GL_TRIANGLES, cast(int) geometry.shared_index_count, GL_UNSIGNED_INT,
                       cast(void*) (geometry.shared_index_start * uint.sizeof));

        // vertex_buffer.mark_segment_submitted();
        // index_buffer.mark_segment_submitted();
    }
    
    void flush_and_render(T)(T geometry) {
        ShapeGroup converted_geometry;
        converted_geometry.shared_vertex_start = geometry.shared_vertex_start;
        converted_geometry.shared_vertex_count = geometry.shared_vertex_count;
        converted_geometry.shared_index_start  = geometry.shared_index_start;
        converted_geometry.shared_index_count  = geometry.shared_index_count;

        record_draw_call_stats(converted_geometry);
        
        glBindFramebuffer(GL_FRAMEBUFFER, efb_fbo);
        
        apply_opengl_state(render_state);
        submit_geometry_to_opengl(converted_geometry, render_state);
    }
    
    void debug_draw_texture(Texture texture, int x, int y, int w, int h) {
    }

    // Emit a GL debug marker via KHR_debug; shows up in RenderDoc when a debug context is active.
    void gl_debug_marker(T...)(string fmt, T args) {
        if (!config_enable_gl_debug_output) {
            return;
        }

        string msg = format(fmt, args);
        glDebugMessageInsert(GL_DEBUG_SOURCE_APPLICATION,
                             GL_DEBUG_TYPE_MARKER,
                             0,
                             GL_DEBUG_SEVERITY_NOTIFICATION,
                             cast(GLsizei) msg.length,
                             msg.ptr);
    }
    
    void efb_copy_to_xfb() {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, efb_fbo);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, xfb_fbo);

        glColorMask(true, true, true, true);
        glBlitFramebuffer(
            render_state.efb_src_x, 
            528 - (render_state.efb_src_y + render_state.efb_src_h),
            render_state.efb_src_x + render_state.efb_src_w, 
            528 - (render_state.efb_src_y + render_state.efb_src_h) + render_state.efb_src_h, 
            render_state.efb_src_x,
            528 - (render_state.efb_src_y + render_state.efb_src_h),
            render_state.efb_src_x + render_state.efb_src_w, 
            528 - (render_state.efb_src_y + render_state.efb_src_h) + render_state.efb_src_h, 
            GL_COLOR_BUFFER_BIT, GL_LINEAR
        );
        
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        xfb_has_data = true;
        clear_tracked_efb_copies();
        
        gl_object_manager.deallocate_all_objects();

        log_and_reset_draw_call_stats();
    }

    void efb_copy_to_texture(u8* buffer, u32 copy_addr, u8 copy_format) {
        apply_opengl_state(render_state);

        // glColorMask(true, true, true, true);
        glReadBuffer(GL_COLOR_ATTACHMENT0);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, efb_fbo);
        gl_debug_marker("EFB copy to texture addr=0x%x fmt=%d from (%d, %d) to (%d %d) {%d %d} to {%d %d} [%d]", 
            copy_addr, copy_format, 
            render_state.efb_src_x, 
            render_state.viewport_height - render_state.efb_src_y - render_state.efb_src_h, 
            render_state.efb_src_x + render_state.efb_src_w, 
            render_state.viewport_height - render_state.efb_src_y,
            render_state.efb_src_x, 
            render_state.efb_src_y, 
            render_state.efb_src_w, 
            render_state.efb_src_h,
            render_state.viewport_height);

        track_efb_copy(copy_addr);
        glReadPixels(
            render_state.efb_src_x, 
            528 - render_state.efb_src_y - render_state.efb_src_h, 
            render_state.efb_src_w, 
            render_state.efb_src_h, 
            GL_RGBA, GL_UNSIGNED_BYTE, buffer
        );
    }
    
    void clear_efb() {
        apply_opengl_state(render_state);

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
        if (render_state.viewport_x != gl_x ||
            render_state.viewport_y != gl_y ||
            render_state.viewport_width != gl_width ||
            render_state.viewport_height != gl_height) {
            flush();
        }

        render_state.viewport_width = gl_width;
        render_state.viewport_height = gl_height;
        render_state.viewport_x = gl_x;
        render_state.viewport_y = gl_y;
    }

    void update_depth_range(float near, float far) {
        if (render_state.viewport_near != near ||
            render_state.viewport_far != far) {
            flush();
            import std.stdio;
            writefln("Updating depth range to near=%.6f far=%.6f", near, far);
        }

        render_state.viewport_near = near;
        render_state.viewport_far = far;
    }
    
    void render_xfb() {
        if (xfb_has_data) {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glDisable(GL_DEPTH_TEST);
            glDisable(GL_BLEND);
            glDisable(GL_SCISSOR_TEST);
            glViewport(0, 0, 640, 528);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, xfb_color_texture);
            glUseProgram(xfb_shader_program);
            glUniform1i(glGetUniformLocation(xfb_shader_program, "u_texture"), 0);
            glBindVertexArray(xfb_vao);
            glDrawArrays(GL_TRIANGLES, 0, 6);
            glBindVertexArray(0);
        }
    }

    private void record_draw_call_stats(ShapeGroup geometry) {
        static if (config_enable_gpu_draw_stats) {
            draw_call_vertex_counts ~= cast(int) geometry.shared_vertex_count;
        }
    }

    private void log_and_reset_draw_call_stats() {
        static if (config_enable_gpu_draw_stats) {
            scope(exit) {
                draw_call_vertex_counts.length = 0;
                efb_copy_count = 0;
            }

            auto draw_call_count = draw_call_vertex_counts.length;
            auto efb_copies = efb_copy_count;

            if (draw_call_count == 0) {
                if (efb_copies) {
                    writefln("Draw call stats: none this frame, efb_copies=%d", efb_copies);
                }
                return;
            }

            double sum = 0;
            int min_value = int.max;
            int max_value = int.min;
            int[int] frequency;

            foreach (value; draw_call_vertex_counts) {
                sum += value;
                min_value = value < min_value ? value : min_value;
                max_value = value > max_value ? value : max_value;
                frequency[value] += 1;
            }

            double mean = sum / cast(double) draw_call_count;

            double variance = 0;
            foreach (value; draw_call_vertex_counts) {
                double diff = value - mean;
                variance += diff * diff;
            }
            variance /= cast(double) draw_call_count;
            double stddev = sqrt(variance);

            auto sorted = draw_call_vertex_counts.dup;
            sort(sorted);
            double median = (draw_call_count % 2)
                ? cast(double) sorted[draw_call_count / 2]
                : (cast(double) (sorted[draw_call_count / 2 - 1] + sorted[draw_call_count / 2])) / 2.0;

            int mode_value = sorted[0];
            int mode_count = 0;
            foreach (key, freq; frequency) {
                if (freq > mode_count || (freq == mode_count && key < mode_value)) {
                    mode_count = freq;
                    mode_value = key;
                }
            }

            int range = max_value - min_value;

            writefln("Draw call stats: count=%d mean=%.2f median=%.2f mode=%d range=%d stddev=%.2f efb_copies=%d",
                     draw_call_count, mean, median, mode_value, range, stddev, efb_copies);
        }
        
        static if (config_enable_opengl_buffer_wait_stats) {
            log_buffer_wait_stats();
        }
    }
    
    static if (config_enable_opengl_buffer_wait_stats) {
        private void log_buffer_wait_stats() {
            auto vertex_waits = vertex_buffer.consume_wait_stats();
            auto index_waits = index_buffer.consume_wait_stats();

            if (vertex_waits.total_waits == 0 && index_waits.total_waits == 0) {
                return;
            }

            writefln("Buffer wait stats: %s total=%d per_segment=%(%d %) ; %s total=%d per_segment=%(%d %)",
                     vertex_buffer.get_debug_name(), vertex_waits.total_waits, vertex_waits.per_segment,
                     index_buffer.get_debug_name(),  index_waits.total_waits,  index_waits.per_segment);
        }
    }
}
