#version 330 core

layout(std140) uniform EFBCopyParams {
    ivec4 channel_mask;
    vec2 src_offset;
    vec2 src_size;
};

uniform sampler2D efb_color;

in vec2 uv;
out vec4 FragColor;

void main() {
    vec4 src_color = texture(efb_color, uv);
    
    FragColor = vec4(
        channel_mask.r != 0 ? src_color.r : 0.0,
        channel_mask.g != 0 ? src_color.g : 0.0, 
        channel_mask.b != 0 ? src_color.b : 0.0,
        channel_mask.a != 0 ? src_color.a : 0.0
    );
}