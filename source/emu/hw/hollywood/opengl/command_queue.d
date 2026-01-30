module emu.hw.hollywood.opengl.command_queue;

enum RenderCommandKind : ubyte {
    Invalid,
    SetState,
    Draw,
    UploadTexture,
    UploadBuffer,
    Clear,
    EfbCopy,
    Fence,
    Present,
    Quit
}

alias BufferHandle  = uint;
alias TextureHandle = uint;
alias StateHandle   = uint;
alias FenceId       = ulong;
alias FrameId       = ulong;

struct GeometrySlice {
    uint index_start;
    uint index_count;
    int  base_vertex;
}

struct SetStateCommand {
    StateHandle state;
}

struct DrawCommand {
    GeometrySlice geometry;
}

struct UploadTextureCommand {
    TextureHandle texture;
    uint          level;
    uint          width;
    uint          height;
    uint          format;
    size_t        byte_offset;
    size_t        byte_size;
}

struct UploadBufferCommand {
    BufferHandle buffer;
    size_t       buffer_offset;
    size_t       byte_size;
    size_t       staging_offset;
}

struct ClearCommand {
    bool     clear_color;
    bool     clear_depth;
    float[4] color;
    float    depth;
}

struct EfbCopyCommand {
    bool to_xfb;
    uint src_x;
    uint src_y;
    uint width;
    uint height;
    uint format;
    bool mipmap;
}

struct FenceCommand {
    FenceId id;
}

struct PresentCommand {
    FrameId frame;
}

struct RenderCommand {
    RenderCommandKind kind = RenderCommandKind.Invalid;
    union {
        SetStateCommand      set_state;
        DrawCommand          draw;
        UploadTextureCommand upload_texture;
        UploadBufferCommand  upload_buffer;
        ClearCommand         clear;
        EfbCopyCommand       efb_copy;
        FenceCommand         fence;
        PresentCommand       present;
    }
}
