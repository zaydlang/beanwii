#version 330 core

layout(std140) uniform EFBCopyParams {
    ivec4 channel_mask;
    vec2 src_offset;
    vec2 src_size;
};

layout(location = 0) in vec2 position;

out vec2 uv;

void main() {
    gl_Position = vec4(position, 0.0, 1.0);
    
    vec2 base_uv = position * 0.5 + 0.5;
    vec2 pixel_coord = src_offset + base_uv * src_size;
    uv = pixel_coord / vec2(640, 528);
    
    gl_Position.y = -gl_Position.y;
    uv.y = 1.0 - uv.y;

    // rotate 90 ccw
    uv = vec2(uv.y, -uv.x);
}