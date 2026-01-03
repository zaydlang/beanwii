module config;

enum MemStrategy {
    SoftwareMem,
    HardwareAcceleratedMem,
}

enum VertexDecoderStrategy {
    Interpreter,
    Jit,
}

// chosen configs - free to modify
enum MemStrategy           config_chosen_mem_strategy            = MemStrategy.HardwareAcceleratedMem;
enum bool                  config_enable_basic_block_linking     = true;
enum bool                  config_enable_debugger                = false;
enum bool                  config_always_efb_copy_to_ram         = false;
enum bool                  config_cache_display_lists            = true;
enum VertexDecoderStrategy config_chosen_vertex_decoder_strategy = VertexDecoderStrategy.Interpreter;
enum bool                  config_enable_gl_debug_output         = false;
enum bool                  config_enable_gpu_draw_stats          = true;

// constraint enforcement
bool implies(bool a, bool b) {
    return !a || b;
}

static assert(config_always_efb_copy_to_ram.implies(config_chosen_mem_strategy == MemStrategy.HardwareAcceleratedMem));
static assert(config_cache_display_lists.implies(config_chosen_mem_strategy == MemStrategy.HardwareAcceleratedMem));
static assert((config_chosen_vertex_decoder_strategy == VertexDecoderStrategy.Jit).implies(config_chosen_mem_strategy == MemStrategy.HardwareAcceleratedMem));
