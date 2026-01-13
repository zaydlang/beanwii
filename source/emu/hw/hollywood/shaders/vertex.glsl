#version 420

in  vec3 in_Position;
in  vec3 normal;
in  vec3 binormal_t;
in  vec3 binormal_b;

in vec2 texcoord[8];

in vec4 in_color[2];
in int matrix_index;

uniform mat4x3 normal_matrix;
out vec3 UV[8];
out vec4 frag_color;
out vec4 color0;
out vec4 color1;

uniform mat4x3 position_matrix;
uniform mat4x3 texture_matrix;
uniform float matrix_data[256];
uniform float normal_matrix_data[256];
uniform mat4 MVP;

struct TexConfig {
	mat3x4 tex_matrix;
	mat3x4 dualtex_matrix;
	bool normalize_before_dualtex;
	int texcoord_source;
	int texmatrix_size;
	int uses_stq;
};

struct ChannelControl {
	uint enable;
	uint ambient_src;
	uint material_src;
	uint light_mask;
	uint diffuse_fn;
	uint attenuation_fn;
	uint padding0;
	uint padding1;
};

struct Light {
	vec4 position;
	vec4 direction;
	vec4 color;
	vec4 dist_atten;
	vec4 spec_atten;
};

layout (std140, binding = 0) uniform VertexConfig {
	TexConfig tex_configs[8];
	ChannelControl color_channel_controls[2];
	ChannelControl alpha_channel_controls[2];
	Light lights[8];

	vec4 ambient_colors[2];
	vec4 material_colors[2];
	int end; // used to verify the size of tex_configs[8] by getting the offset of end
};

vec3 get_texcoord(int idx) {
	vec3 result = vec3(0.0, 0.0, 1.0);
	switch (tex_configs[idx].texcoord_source) {
		case 0: result = vec3(in_Position.xyz); break;
		case 1: result = normal; break;
		case 2: result = vec3(in_color[0].rgb); break;
		case 3: result = binormal_t; break;
		case 4: result = binormal_b; break;
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

mat4x3 get_matrix(int index) {
	int base = index * 4;
	
	return mat4x3(
		matrix_data[base+0], matrix_data[base+4], matrix_data[base+8],
		matrix_data[base+1], matrix_data[base+5], matrix_data[base+9],
		matrix_data[base+2], matrix_data[base+6], matrix_data[base+10],
		matrix_data[base+3], matrix_data[base+7], matrix_data[base+11]
	);
}

mat4x3 get_normal_matrix(int index) {
	int base = index * 4;

	return mat4x3(
		normal_matrix_data[base+0], normal_matrix_data[base+4], normal_matrix_data[base+8],
		normal_matrix_data[base+1], normal_matrix_data[base+5], normal_matrix_data[base+9],
		normal_matrix_data[base+2], normal_matrix_data[base+6], normal_matrix_data[base+10],
		normal_matrix_data[base+3], normal_matrix_data[base+7], normal_matrix_data[base+11]
	);
}

vec3 calculate_light_rgb(int i, vec3 pos_view, vec3 n) {
	ChannelControl cc = color_channel_controls[i];

	vec3 ambient = cc.ambient_src == 0 ? ambient_colors[i].rgb : in_color[i].rgb;

	vec3 light_func = ambient;
	
	for (int j = 0; j < 8; ++j) {
		if ((cc.light_mask & (1 << j)) == 0) continue;

		Light l = lights[j];
		vec3 diff = l.position.xyz - pos_view;
		float d = length(diff);
		vec3 ln = normalize(diff);

		float diffuse = 1.0;
		if (cc.diffuse_fn == 2) {
			diffuse = max(dot(n, ln), 0.0);
		} else if (cc.diffuse_fn == 1) {
			diffuse = 0.5 * dot(n, ln) + 0.5;
		} // GX_DF_NONE leaves it at 1.0

		float atten = 1.0;
		if (cc.attenuation_fn == 3) {
			float cosTheta = dot(normalize(l.direction.xyz), ln);
			float num = max(l.dist_atten[2] * cosTheta * cosTheta + l.dist_atten[1] * cosTheta + l.dist_atten[0], 0.0);
			float den = l.spec_atten[2] * d * d + l.spec_atten[1] * d + l.spec_atten[0];
			atten = (den != 0.0) ? num / den : 0.0;
		} else if (cc.attenuation_fn == 1) {
			float ndh = clamp(dot(n, normalize(l.direction.xyz)), -1.0, 1.0);
			float num = max(l.dist_atten[2] * ndh * ndh + l.dist_atten[1] * ndh + l.dist_atten[0], 0.0);
			float den = l.spec_atten[2] * ndh * ndh + l.spec_atten[1] * ndh + l.spec_atten[0];
			atten = (den != 0.0) ? num / den : 0.0;
			diffuse = 1.0;
		} // GX_AF_NONE leaves it at 1.0

		light_func += atten * diffuse * l.color.rgb;
	}

	return light_func;
}

float calculate_light_a(int i) {
	return 0.0;
}

void main(void) {
	mat4x3 transform_matrix;
	mat4x3 normal_transform;
	
	if (matrix_index >= 0) {
		transform_matrix = get_matrix(matrix_index);
		normal_transform = get_normal_matrix(matrix_index);
	} else {
		transform_matrix = position_matrix;
		normal_transform = normal_matrix;
	}
	
	vec3 pos_view = transform_matrix * vec4(in_Position, 1.0);
	vec3 n = normalize(normal_transform * vec4(normal, 0.0));
	gl_Position = MVP * vec4(pos_view, 1.0);
	// gl_Position.z = -gl_Position.z;
	
	// texcoord calculations
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

	// lighting calculations
	vec4 color_output[2];

	for (int i = 0; i < 2; i++) {
		ChannelControl cc = color_channel_controls[i];
		ChannelControl ca = alpha_channel_controls[i];

		vec4 material = vec4(
			cc.material_src == 0 ? material_colors[i].rgb : in_color[i].rgb,
			ca.material_src == 0 ? material_colors[i].a   : in_color[i].a
		);
			
			vec4 light_func = vec4(
				cc.enable == 0 ? vec3(1.0) : calculate_light_rgb(i, pos_view, n),
				ca.enable == 0 ? 1.0 : calculate_light_a(i)
			);
				
			color_output[i] = material * light_func;
		}

	color0 = color_output[0];
	color1 = color_output[1];
}
