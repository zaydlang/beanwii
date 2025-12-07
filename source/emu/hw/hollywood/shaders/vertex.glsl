#version 420

in  vec3 in_Position;
in  vec3 normal;

in vec2 texcoord[8];

in vec4 in_color[2];

out vec3 UV[8];
out vec4 frag_color;
out vec4 color0;
out vec4 color1;

uniform mat4x3 position_matrix;
uniform mat4x3 texture_matrix;
uniform mat4 MVP;

struct TexConfig {
	mat3x4 tex_matrix;
	mat3x4 dualtex_matrix;
	bool normalize_before_dualtex;
	int texcoord_source;
	int texmatrix_size;
	int uses_stq;
};

layout (std140, binding = 0) uniform VertexConfig {
	TexConfig tex_configs[8];
	int end; // used to verify the size of tex_configs[8] by getting the offset of end
};

vec3 get_texcoord(int idx) {
	vec3 result = vec3(0.0, 0.0, 1.0);
	switch (tex_configs[idx].texcoord_source) {
		case 0: result = vec3(in_Position.xyz); break;
		case 5: result = vec3(texcoord[0], 1.0); break;
		case 6: result = vec3(texcoord[1], 1.0); break;
		case 7: result = vec3(texcoord[2], 1.0); break;
		case 8: result = vec3(texcoord[3], 1.0); break;
		case 9: result = vec3(texcoord[4], 1.0); break;
		case 10: result = vec3(texcoord[5], 1.0); break;
		case 11: result = vec3(texcoord[6], 1.0); break;
		case 12: result = vec3(texcoord[7], 1.0); break;
	}

	if (tex_configs[idx].uses_stq == 0) {
		result = vec3(result.xy, 1.0);
	}

	return result;
}

void main(void) {
	gl_Position = MVP * vec4(position_matrix * vec4(in_Position, 1.0), 1.0);

	for (int i = 0; i < 8; i++) {
		vec3 src = get_texcoord(i);
		vec3 coord = transpose(tex_configs[i].tex_matrix) * vec4(src, 1.0);

		if (tex_configs[i].texmatrix_size == 2) {
			coord.z = 1.0;
		}

		if (tex_configs[i].normalize_before_dualtex) {
			coord = normalize(coord);
		}

		vec3 post = transpose(tex_configs[i].dualtex_matrix) * vec4(coord, 1.0);
		
		if (tex_configs[i].texmatrix_size == 2) {
			post.z = 1.0;
		}

		UV[i] = post;
	}

	color0 = in_color[0];
	color1 = in_color[1];
}
