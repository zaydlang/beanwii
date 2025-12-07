#version 420

out vec4 out_Color;

in vec3 UV[8];
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
	int color_op;
	int in_alfa_a;
	int in_alfa_b;
	int in_alfa_c;
	int in_alfa_d;
	int alfa_op;
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
    int texmap_enable;
	int clamp_color;
	int clamp_alfa;
	int kcsel;
	int kasel;
};

layout (std140, binding = 1) uniform TevConfig {
	TevStage stages[16];
	uniform vec4 reg0;
	uniform vec4 reg1;
	uniform vec4 reg2;
	uniform vec4 reg3;
	uniform vec4 k0;
	uniform vec4 k1;
	uniform vec4 k2;
	uniform vec4 k3;
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
	vec3 texcoord = UV[stages[stage].texcoord];
	vec2 proj = texcoord.xy / texcoord.z;
	
	switch (texmap) {
		case 0: return texture(wiiscreen0, proj.yx);
		case 1: return texture(wiiscreen1, proj.yx);
		case 2: return texture(wiiscreen2, proj.yx);
		case 3: return texture(wiiscreen3, proj.yx);
		case 4: return texture(wiiscreen4, proj.yx);
		case 5: return texture(wiiscreen5, proj.yx);
		case 6: return texture(wiiscreen6, proj.yx);
		case 7: return texture(wiiscreen7, proj.yx);
	}
}

vec3 resolve_kcsel(int kcsel) {
	switch (kcsel) {
		case 0x00: return vec3(1.0);
		case 0x01: return vec3(7.0 / 8.0);
		case 0x02: return vec3(3.0 / 4.0);
		case 0x03: return vec3(5.0 / 8.0);
		case 0x04: return vec3(0.5);
		case 0x05: return vec3(3.0 / 8.0);
		case 0x06: return vec3(0.25);
		case 0x07: return vec3(1.0 / 8.0);
		case 0x0C: return k0.rgb;
		case 0x0D: return k1.rgb;
		case 0x0E: return k2.rgb;
		case 0x0F: return k3.rgb;
		case 0x10: return k0.rrr;
		case 0x11: return k1.rrr;
		case 0x12: return k2.rrr;
		case 0x13: return k3.rrr;
		case 0x14: return k0.ggg;
		case 0x15: return k1.ggg;
		case 0x16: return k2.ggg;
		case 0x17: return k3.ggg;
		case 0x18: return k0.bbb;
		case 0x19: return k1.bbb;
		case 0x1A: return k2.bbb;
		case 0x1B: return k3.bbb;
		default:   return vec3(0.0);
	}
}

vec3 resolve_kasel(int kasel) {
	switch (kasel) {
		case 0x00: return vec3(1.0);
		case 0x01: return vec3(7.0 / 8.0);
		case 0x02: return vec3(3.0 / 4.0);
		case 0x03: return vec3(5.0 / 8.0);
		case 0x04: return vec3(0.5);
		case 0x05: return vec3(3.0 / 8.0);
		case 0x06: return vec3(0.25);
		case 0x07: return vec3(1.0 / 8.0);
		case 0x10: return k0.rrr;
		case 0x11: return k1.rrr;
		case 0x12: return k2.rrr;
		case 0x13: return k3.rrr;
		case 0x14: return k0.ggg;
		case 0x15: return k1.ggg;
		case 0x16: return k2.ggg;
		case 0x17: return k3.ggg;
		case 0x18: return k0.bbb;
		case 0x19: return k1.bbb;
		case 0x1A: return k2.bbb;
		case 0x1B: return k3.bbb;
		case 0x1C: return k0.aaa;
		case 0x1D: return k1.aaa;
		case 0x1E: return k2.aaa;
		case 0x1F: return k3.aaa;
		default:   return vec3(0.0);
	}
}

vec3 get_parameter_for_color_stage(int idx, int stage) {
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
		case 14: return resolve_kcsel(stages[stage].kcsel);
		case 15: return vec3(0.0, 0.0, 0.0);
	}
}

vec3 get_parameter_for_alfa_stage(int idx, int stage) {
	switch (idx) {
		case 0: return color_regs[0].aaa; // ??????????  http://www.amnoid.de/gc/tev.html
		case 1: return color_regs[1].aaa;
		case 2: return color_regs[2].aaa;
		case 3: return color_regs[3].aaa;
		case 4: return sample_texture(stage).aaa;
		case 5: return get_color_from_ras_channel_id(stages[idx].ras_channel_id, stage).aaa;
		case 6: return resolve_kasel(stages[stage].kasel);
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
		vec3 ca = get_parameter_for_color_stage(stages[i].in_color_a, i);
		vec3 cb = get_parameter_for_color_stage(stages[i].in_color_b, i);
		vec3 cc = get_parameter_for_color_stage(stages[i].in_color_c, i);
		vec3 cd = get_parameter_for_color_stage(stages[i].in_color_d, i);
		vec3 aa = get_parameter_for_alfa_stage(stages[i].in_alfa_a,   i);
		vec3 ab = get_parameter_for_alfa_stage(stages[i].in_alfa_b,   i);
		vec3 ac = get_parameter_for_alfa_stage(stages[i].in_alfa_c,   i);
		vec3 ad = get_parameter_for_alfa_stage(stages[i].in_alfa_d,   i);

		if (stages[i].color_op >= 8) {
			uint a_r = uint(round(ca.r * 255.0));
			uint a_g = uint(round(ca.g * 255.0));
			uint a_b = uint(round(ca.b * 255.0));
			uint b_r = uint(round(cb.r * 255.0));
			uint b_g = uint(round(cb.g * 255.0));
			uint b_b = uint(round(cb.b * 255.0));

			uint operand_a;
			uint operand_b;
			int op = stages[i].color_op;

			if (op == 10 || op == 11) {
				operand_a = (a_g << 8) | a_r;
				operand_b = (b_g << 8) | b_r;
			} else if (op == 12 || op == 13) {
				operand_a = (a_b << 16) | (a_g << 8) | a_r;
				operand_b = (b_b << 16) | (b_g << 8) | b_r;
			} else if (op == 14 || op == 15) {
				operand_a = (a_r << 16) | (a_g << 8) | a_b;
				operand_b = (b_r << 16) | (b_g << 8) | b_b;
			} else {
				operand_a = a_r;
				operand_b = b_r;
			}

			bool cond = (op & 1) == 0 ? (operand_a > operand_b) : (operand_a == operand_b);
			last_color_dest = cond ? cc : cd;
		} else {
			last_color_dest = (cd + ((1 - cc) * ca + cc * cb) + vec3(stages[i].bias_color)) * vec3(stages[i].scale_color);
		}

		if (stages[i].alfa_op >= 8) {
			uint a_r = uint(round(aa.r * 255.0));
			uint b_r = uint(round(ab.r * 255.0));
			int op = stages[i].alfa_op;
			bool cond = (op & 1) == 0 ? (a_r > b_r) : (a_r == b_r);
			last_alfa_dest = (cond ? ac : ad).r;
		} else {
			last_alfa_dest = ((ad + ((1 - ac) * aa + ac * ab) + vec3(stages[i].bias_alfa)) * vec3(stages[i].scale_alfa)).x;
		}

		if (stages[i].clamp_color != 0) {
			last_color_dest = clamp(last_color_dest, 0.0, 1.0);
		}
		
		if (stages[i].clamp_alfa != 0) {
			last_alfa_dest = clamp(last_alfa_dest, 0.0, 1.0);
		}

		color_regs[stages[i].color_dest].rgb = last_color_dest;
		color_regs[stages[i].alfa_dest].a = last_alfa_dest;
	}

	// last_alfa_dest = 1;
	out_Color = vec4(last_color_dest, last_alfa_dest);

	if (last_alfa_dest == 0) {
		discard;
	}
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
