#version 420

in  vec3 in_Position;
in  vec3 normal;

in vec2 texcoord[8];

in vec4 in_color[2];

out vec2 UV[8];
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
};

layout (std140, binding = 0) uniform VertexConfig {
	TexConfig tex_configs[8];
	int end; // used to verify the size of tex_configs[8] by getting the offset of end
};

vec2 get_texcoord(int idx) {
	switch (tex_configs[idx].texcoord_source) {
		case 0: return vec2(0);
		case 1: return vec2(0);
		case 2: return vec2(0);
		case 3: return vec2(0);
		case 4: return vec2(0);

		case 5:
		case 6:
		case 7:
		case 8:
		case 9:
		case 10:
		case 11:
		case 12:
			return texcoord[tex_configs[idx].texcoord_source - 5];
	}
}

void main(void) {
	gl_Position = MVP * vec4(position_matrix * vec4(in_Position, 1.0), 1.0);

	for (int i = 0; i < 8; i++) {
		vec4 coord = vec4(transpose(tex_configs[i].tex_matrix) * vec4(get_texcoord(i), 1.0, 1.0), 1.0);

		// UV[i] = coord.xy;
		// UV[i] = texcoord[i];
		if (tex_configs[i].normalize_before_dualtex) {
			coord = normalize(coord);
		}

		// UV[i] = coord.xy;
		UV[i] = (transpose(tex_configs[i].dualtex_matrix) * coord).xy;
	// UV[i] = (tex_configs[i] * vec4(texcoord[i], 1.0, 1.0)).xy;
	}

	color0 = in_color[0];
	color1 = in_color[1];
}