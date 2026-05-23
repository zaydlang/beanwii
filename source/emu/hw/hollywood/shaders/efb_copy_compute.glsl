#version 430 core

layout(local_size_x = 16, local_size_y = 8, local_size_z = 1) in;

layout(binding = 0) uniform sampler2D efb_color;
layout(binding = 0, rgba8) writeonly uniform image2D dst;

layout(std140, binding = 0) uniform EFBCopyParams {
    ivec4 channel_mask;
    vec2  src_offset;
    vec2  src_size;
    ivec2 dst_size;
    ivec2 efb_size;
};

void main() {
    ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
    if (gid.x >= dst_size.x || gid.y >= dst_size.y) {
        return;
    }

    vec2 base_uv = (vec2(gid) + 0.5) / vec2(dst_size);
	vec2 offset = src_offset;
	offset.y = float(efb_size.y) - src_size.y - src_offset.y;
    vec2 pixel_coord = offset + base_uv * src_size;
    vec2 uv = pixel_coord / vec2(efb_size);

    vec4 src_color = texture(efb_color, uv);
    vec4 masked = vec4(
        channel_mask.r != 0 ? src_color.r : 0.0,
        channel_mask.g != 0 ? src_color.g : 0.0,
        channel_mask.b != 0 ? src_color.b : 0.0,
        channel_mask.a != 0 ? src_color.a : 0.0
    );

	// Flip into top-left-origin texture space without writing past the last row.
	gid.y = dst_size.y - 1 - gid.y;
    imageStore(dst, gid, masked);
}
