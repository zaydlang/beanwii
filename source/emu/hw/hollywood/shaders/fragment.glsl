#version 420

out vec4 out_Color;

in vec2 UV[8];
in vec4 frag_color;
in vec4 color0;
in vec4 color1;

uniform sampler2D wiiscreen0;
uniform sampler2D wiiscreen1;
uniform sampler2D wiiscreen2;
uniform sampler2D wiiscreen3;
uniform sampler2D wiiscreen4;
uniform sampler2D wiiscreen5;
uniform sampler2D wiiscreen6;
uniform sampler2D wiiscreen7;

struct TevStage {
	int in_color_a;
	int in_color_b;
	int in_color_c;
	int in_color_d;
	int in_alfa_a;
	int in_alfa_b;
	int in_alfa_c;
	int in_alfa_d;
	int color_dest;
	int alfa_dest;
	float bias_color;
	float scale_color;
	float bias_alfa;
	float scale_alfa;
	int ras_channel_id;
	int ras_swap_table_index;
	int tex_swap_table_index;
	int texmap;
	int texcoord;
};

layout (std140, binding = 1) uniform TevConfig {
	TevStage stages[16];
	uniform vec4 reg0;
	uniform vec4 reg1;
	uniform vec4 reg2;
	uniform vec4 reg3;
	uniform int num_tev_stages;
	uniform int swap_tables;
};

vec4 color_regs[4];

vec4 get_color_from_ras_channel_id(int ras_channel_id, int stage) {
	vec4 ras;

	switch (ras_channel_id) {
		case 0: ras = color0; break;
		case 1: ras = color1; break;
		case 2: ras = vec4(1.0); break;
		case 3: ras = vec4(1.0); break;
		case 4: ras = vec4(1.0); break;
		case 5: ras = vec4(1.0); break;
		case 6: ras = vec4(1.0); break;
		case 7: ras = vec4(1.0); break;
	}

	int swap = (swap_tables >> (stages[stage].ras_swap_table_index * 8)) & 0xFF;
	
	vec4 result;
	result[0] = ras[(swap >> 0) & 3];
	result[1] = ras[(swap >> 2) & 3];
	result[2] = ras[(swap >> 4) & 3];
	result[3] = ras[(swap >> 6) & 3];
	return ras;
}

vec4 sample_texture(int stage) {
	int texmap = stages[stage].texmap;
	vec2 texcoord = UV[stages[stage].texcoord].yx;
	
	switch (texmap) {
		case 0: return texture(wiiscreen0, texcoord);
		case 1: return texture(wiiscreen1, texcoord);
		case 2: return texture(wiiscreen2, texcoord);
		case 3: return texture(wiiscreen3, texcoord);
		case 4: return texture(wiiscreen4, texcoord);
		case 5: return texture(wiiscreen5, texcoord);
		case 6: return texture(wiiscreen6, texcoord);
		case 7: return texture(wiiscreen7, texcoord);
	}
}

vec3 get_parameter_for_color_stage(int idx, int stage, vec4 konst) {
	switch (idx) {
		case 0: return color_regs[0].rgb;
		case 1: return color_regs[0].aaa;
		case 2: return color_regs[1].rgb;
		case 3: return color_regs[1].aaa;
		case 4: return color_regs[2].rgb;
		case 5: return color_regs[2].aaa;
		case 6: return color_regs[3].rgb;
		case 7: return color_regs[3].aaa;
		case 8: return sample_texture(stage).rgb;
		case 9: return sample_texture(stage).aaa;
		case 10: return get_color_from_ras_channel_id(stages[idx].ras_channel_id, stage).rgb;
		case 11: return get_color_from_ras_channel_id(stages[idx].ras_channel_id, stage).aaa;
		case 12: return vec3(1.0, 1.0, 1.0);
		case 13: return vec3(0.5, 0.5, 0.5);
		case 14: return konst.rgb; 
		case 15: return vec3(0.0, 0.0, 0.0);
	}
}

vec3 get_parameter_for_alfa_stage(int idx, int stage, vec4 konst) {
	switch (idx) {
		case 0: return color_regs[0].aaa; // ??????????  http://www.amnoid.de/gc/tev.html
		case 1: return color_regs[1].aaa;
		case 2: return color_regs[2].aaa;
		case 3: return color_regs[3].aaa;
		case 4: return sample_texture(stage).aaa;
		case 5: return get_color_from_ras_channel_id(stages[idx].ras_channel_id, stage).aaa;
		case 6: return vec3(1.0);
		case 7: return vec3(0.0);
	}
}

void main(void) {
	vec3 last_color_dest;
	float last_alfa_dest;

	color_regs[0] = reg0;
	color_regs[1] = reg1;
	color_regs[2] = reg2;
	color_regs[3] = reg3;

	for (int i = 0; i < num_tev_stages; i++) {
		vec3 ca = get_parameter_for_color_stage(stages[i].in_color_a, i, vec4(1));
		vec3 cb = get_parameter_for_color_stage(stages[i].in_color_b, i, vec4(1));
		vec3 cc = get_parameter_for_color_stage(stages[i].in_color_c, i, vec4(1));
		vec3 cd = get_parameter_for_color_stage(stages[i].in_color_d, i, vec4(1));
		vec3 aa = get_parameter_for_alfa_stage(stages[i].in_alfa_a,   i, vec4(1));
		vec3 ab = get_parameter_for_alfa_stage(stages[i].in_alfa_b,   i, vec4(1));
		vec3 ac = get_parameter_for_alfa_stage(stages[i].in_alfa_c,   i, vec4(1));
		vec3 ad = get_parameter_for_alfa_stage(stages[i].in_alfa_d,   i, vec4(1));

		last_color_dest = (cd + ((1 - cc) * ca + cc * cb) + vec3(stages[i].bias_color)) * vec3(stages[i].scale_color);
		last_alfa_dest = ((ad + ((1 - ac) * aa + ac * ab) + vec3(stages[i].bias_alfa)) * vec3(stages[i].scale_alfa)).x;

		color_regs[stages[i].color_dest].rgb = last_color_dest;
		color_regs[stages[i].alfa_dest].a = last_alfa_dest;
	}

	// last_alfa_dest = 1;
	out_Color = vec4(last_color_dest, last_alfa_dest);
	// out_Color = vec4(UV[0],UV[1],0,1);

	// if (stages[0].in_alfa_a == 7 && stages[0].in_alfa_b == 7 && stages[0].in_alfa_c == 7 && stages[0].in_alfa_d == 6) {
	// out_Color = vec4(1,0,0,1);
	// } else {
	// out_Color = vec4(0,1,0,texture(wiiscreen, vec2(UV.y, UV.x)).a);
//  }

	// out_Color = konst_a;
	// out_Color = texture(wiiscreen0, vec2(UV[0].y, UV[0].x));

	// if (num_tev_stages == 1) {
		// out_Color = vec4(1.0, 0.0, 0.0, 1.0);
	// } else {
		// out_Color = vec4(0.0, 1.0, 0.0, 1.0);
	// }
}
