#version 430
#extension GL_ARB_gpu_shader_int64 : require

layout(std430, binding = 2) buffer BoundingBox {
    uint bbox_left;
    uint bbox_right;
    uint bbox_top;
    uint bbox_bottom;
};

layout(location = 0, index = 0) out vec4 out_Color0;
layout(location = 0, index = 1) out vec4 out_Color1;

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

struct IndirectStageBinding {
	int texcoord;
	int texmap;
	int scale_s;
	int scale_t;
};

struct IndirectMatrixSlot {
	vec4 row0;
	vec4 row1;
	int scale_exp;
	int _pad0;
	int _pad1;
	int _pad2;
};

struct TevIndirectOp {
	int ind_stage;
	int format;
	int bias_sel;
	int alpha_sel;
	int matrix_sel;
	int wrap_s;
	int wrap_t;
	int add_prev;
	int utc_lod;
	int _pad0;
	int _pad1;
	int _pad2;
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
	uniform int swap_tables_01;
	uniform int swap_tables_23;
	uniform int alpha_comp0;
	uniform int alpha_comp1;
	uniform int alpha_aop;
	uniform int alpha_ref0;
	uniform int alpha_ref1;
	uniform int forced_alpha;
	uniform int is_alpha_forced;
    uniform float zbias;
    uniform int ztexture_fmt;
    uniform int ztexture_op;
	uniform int indirect_block_padding0;
	uniform int indirect_block_padding1;
	uniform int indirect_block_padding2;
	IndirectStageBinding indirect_stages[4];
	IndirectMatrixSlot indirect_matrices[3];
	TevIndirectOp indirect_ops[16];
	uniform int num_ind_stages;
	uniform int indirect_mask;
	uniform int indirect_padding_end0;
	uniform int indirect_padding_end1;
};


vec4 color_regs[4];

uniform int u_efb_scale;

ivec2 get_texture_size(int texmap) {
	switch (texmap) {
		case 0: return textureSize(wiiscreen0, 0);
		case 1: return textureSize(wiiscreen1, 0);
		case 2: return textureSize(wiiscreen2, 0);
		case 3: return textureSize(wiiscreen3, 0);
		case 4: return textureSize(wiiscreen4, 0);
		case 5: return textureSize(wiiscreen5, 0);
		case 6: return textureSize(wiiscreen6, 0);
		case 7: return textureSize(wiiscreen7, 0);
	}

	return ivec2(1);
}

vec4 sample_texture_unit(int texmap, vec2 uv_norm) {
	switch (texmap) {
		case 0: return texture(wiiscreen0, uv_norm);
		case 1: return texture(wiiscreen1, uv_norm);
		case 2: return texture(wiiscreen2, uv_norm);
		case 3: return texture(wiiscreen3, uv_norm);
		case 4: return texture(wiiscreen4, uv_norm);
		case 5: return texture(wiiscreen5, uv_norm);
		case 6: return texture(wiiscreen6, uv_norm);
		case 7: return texture(wiiscreen7, uv_norm);
	}

	return vec4(0.0);
}

vec4 sample_texture_unit_with_grad(int texmap, vec2 uv_norm, vec2 lod_dx_norm, vec2 lod_dy_norm) {
	switch (texmap) {
		case 0: return textureGrad(wiiscreen0, uv_norm, lod_dx_norm, lod_dy_norm);
		case 1: return textureGrad(wiiscreen1, uv_norm, lod_dx_norm, lod_dy_norm);
		case 2: return textureGrad(wiiscreen2, uv_norm, lod_dx_norm, lod_dy_norm);
		case 3: return textureGrad(wiiscreen3, uv_norm, lod_dx_norm, lod_dy_norm);
		case 4: return textureGrad(wiiscreen4, uv_norm, lod_dx_norm, lod_dy_norm);
		case 5: return textureGrad(wiiscreen5, uv_norm, lod_dx_norm, lod_dy_norm);
		case 6: return textureGrad(wiiscreen6, uv_norm, lod_dx_norm, lod_dy_norm);
		case 7: return textureGrad(wiiscreen7, uv_norm, lod_dx_norm, lod_dy_norm);
	}

	return vec4(0.0);
}

vec2 projected_uv_normalized(int texcoord_idx) {
	vec3 texcoord = UV[texcoord_idx];
	return texcoord.xy / texcoord.z;
}

vec2 normalized_to_texel(int texmap, vec2 uv_norm) {
	return uv_norm * max(vec2(get_texture_size(texmap)), vec2(1.0));
}

vec2 texel_to_normalized(int texmap, vec2 uv_texel) {
	return uv_texel / max(vec2(get_texture_size(texmap)), vec2(1.0));
}

float apply_indirect_wrap(float coord, int wrap_mode) {
	switch (wrap_mode) {
		case 0: return coord;
		case 1: return mod(coord, 256.0);
		case 2: return mod(coord, 128.0);
		case 3: return mod(coord, 64.0);
		case 4: return mod(coord, 32.0);
		case 5: return mod(coord, 16.0);
		case 6: return 0.0;
	}

	return coord;
}

int get_indirect_matrix_scale_slot(int matrix_sel) {
	if (matrix_sel >= 1 && matrix_sel <= 3) {
		return matrix_sel - 1;
	}
	if (matrix_sel >= 5 && matrix_sel <= 7) {
		return matrix_sel - 5;
	}
	if (matrix_sel >= 9 && matrix_sel <= 11) {
		return matrix_sel - 9;
	}
	return -1;
}

float get_indirect_matrix_scale(int matrix_sel) {
	int slot = get_indirect_matrix_scale_slot(matrix_sel);
	if (slot >= 0 && slot < 3) {
		return exp2(float(indirect_matrices[slot].scale_exp));
	}
	return 0.0;
}

vec3 decode_indirect_offsets(vec4 sample_rgba, int format, int bias_sel) {
	vec3 sample_bytes = floor(sample_rgba.abg * 255.0 + vec3(0.5));
	vec3 offsets;

	switch (format) {
		case 0: offsets = sample_bytes; break;
		case 1: offsets = floor(sample_bytes / 8.0); break;
		case 2: offsets = floor(sample_bytes / 16.0); break;
		case 3: offsets = floor(sample_bytes / 32.0); break;
		default: offsets = sample_bytes; break;
	}

	float bias_value = format == 0 ? -128.0 : 1.0;
	switch (bias_sel) {
		case 1: offsets.x += bias_value; break;
		case 2: offsets.y += bias_value; break;
		case 3: offsets.xy += vec2(bias_value); break;
		case 4: offsets.z += bias_value; break;
		case 5: offsets.xz += vec2(bias_value); break;
		case 6: offsets.yz += vec2(bias_value); break;
		case 7: offsets += vec3(bias_value); break;
	}

	return offsets;
}

float decode_indirect_bump_alpha_byte(float sample_byte, int format) {
	switch (format) {
		case 0: return floor(sample_byte / 8.0) * 8.0;
		case 1: return mod(sample_byte, 8.0) * 32.0;
		case 2: return mod(sample_byte, 16.0) * 16.0;
		case 3: return mod(sample_byte, 32.0) * 8.0;
		default: return 0.0;
	}
}

float get_indirect_bump_alpha_max_byte(int format) {
	switch (format) {
		case 0: return 248.0;
		case 1: return 224.0;
		case 2: return 240.0;
		case 3: return 248.0;
		default: return 255.0;
	}
}

float compute_indirect_bump_alpha(vec4 sample_rgba, int format, int alpha_sel, bool normalize_to_full_range) {
	if (alpha_sel == 0) {
		return 0.0;
	}

	vec3 sample_bytes = floor(sample_rgba.rgb * 255.0 + vec3(0.5));
	float sample_byte = 0.0;
	switch (alpha_sel) {
		case 1: sample_byte = sample_bytes.x; break;
		case 2: sample_byte = sample_bytes.y; break;
		case 3: sample_byte = sample_bytes.z; break;
		default: return 0.0;
	}

	float plain_byte = decode_indirect_bump_alpha_byte(sample_byte, format);
	if (!normalize_to_full_range) {
		return plain_byte / 255.0;
	}

	float max_byte = get_indirect_bump_alpha_max_byte(format);
	if (max_byte <= 0.0) {
		return 0.0;
	}

	return clamp(plain_byte / max_byte, 0.0, 1.0);
}

vec2 apply_indirect_matrix(int matrix_sel, vec2 incoming_regular_texel, vec3 ind_offsets) {
	float scale = get_indirect_matrix_scale(matrix_sel);
	if (scale == 0.0) {
		return vec2(0.0);
	}

	if (matrix_sel >= 1 && matrix_sel <= 3) {
		int slot = matrix_sel - 1;
		return vec2(
			dot(indirect_matrices[slot].row0.xyz, ind_offsets),
			dot(indirect_matrices[slot].row1.xyz, ind_offsets)
		) * scale;
	}

	if (matrix_sel >= 5 && matrix_sel <= 7) {
		return vec2(incoming_regular_texel.x, incoming_regular_texel.y) * (ind_offsets.x / 256.0) * scale;
	}

	if (matrix_sel >= 9 && matrix_sel <= 11) {
		return vec2(incoming_regular_texel.x, incoming_regular_texel.y) * (ind_offsets.y / 256.0) * scale;
	}

	return vec2(0.0);
}

vec2 compute_indirect_offset_texel(int stage, vec2 incoming_regular_texel, out float bump_alpha_plain, out float bump_alpha_normalized) {
	bump_alpha_plain = 0.0;
	bump_alpha_normalized = 0.0;

	TevIndirectOp op = indirect_ops[stage];
	if (op.ind_stage < 0 || op.ind_stage >= num_ind_stages) {
		return vec2(0.0);
	}

	IndirectStageBinding binding = indirect_stages[op.ind_stage];
	vec2 indirect_texel = normalized_to_texel(binding.texmap, projected_uv_normalized(binding.texcoord));
	vec2 scale_divisor = max(vec2(float(binding.scale_s), float(binding.scale_t)), vec2(1.0));
	vec2 indirect_lookup_norm = texel_to_normalized(binding.texmap, indirect_texel / scale_divisor);
	vec4 indirect_sample = sample_texture_unit(binding.texmap, indirect_lookup_norm);
	vec3 ind_offsets = decode_indirect_offsets(indirect_sample, op.format, op.bias_sel);

	if (stage > 0) {
		bump_alpha_plain = compute_indirect_bump_alpha(indirect_sample, op.format, op.alpha_sel, false);
		bump_alpha_normalized = compute_indirect_bump_alpha(indirect_sample, op.format, op.alpha_sel, true);
	}

	return apply_indirect_matrix(op.matrix_sel, incoming_regular_texel, ind_offsets);
}

vec4 apply_swap_table(vec4 value, int swap_index) {
	uint packed_tables = uint(swap_index < 2 ? swap_tables_01 : swap_tables_23);
	int local_index = swap_index & 1;
	int swap = int((packed_tables >> (local_index * 8)) & 0xFFu);
	vec4 result;
	result[0] = value[(swap >> 0) & 3];
	result[1] = value[(swap >> 2) & 3];
	result[2] = value[(swap >> 4) & 3];
	result[3] = value[(swap >> 6) & 3];
	return result;
}

vec4 get_color_from_ras_channel_id(int ras_channel_id, int stage, float bump_alpha_plain, float bump_alpha_normalized) {
	vec4 ras;

	switch (ras_channel_id) {
		case 0: ras = color0; break;
		case 1: ras = color1; break;
		case 5: ras = vec4(bump_alpha_plain); break;
		case 6: ras = vec4(bump_alpha_normalized); break;
		case 7: ras = vec4(0.0); break;
		default: ras = vec4(1.0); break;
	}

	return apply_swap_table(ras, stages[stage].ras_swap_table_index);
}

void compute_stage_texture_info(int stage, vec2 previous_stage_texel, out vec4 stage_tex, out vec2 final_texel, out float bump_alpha_plain, out float bump_alpha_normalized) {
	int texmap = stages[stage].texmap;
	vec2 original_norm = projected_uv_normalized(stages[stage].texcoord);
	vec2 incoming_regular_texel = normalized_to_texel(texmap, original_norm);
	final_texel = incoming_regular_texel;
	bump_alpha_plain = 0.0;
	bump_alpha_normalized = 0.0;
	bool has_indirect = indirect_ops[stage].ind_stage >= 0 && indirect_ops[stage].ind_stage < num_ind_stages;

	if (has_indirect) {
		vec2 wrapped_texel = vec2(
			apply_indirect_wrap(incoming_regular_texel.x, indirect_ops[stage].wrap_s),
			apply_indirect_wrap(incoming_regular_texel.y, indirect_ops[stage].wrap_t)
		);
		final_texel = wrapped_texel + compute_indirect_offset_texel(stage, incoming_regular_texel, bump_alpha_plain, bump_alpha_normalized);
		if (indirect_ops[stage].add_prev != 0) {
			final_texel += previous_stage_texel;
		}
	}

	if (stages[stage].texmap_enable == 0) {
		stage_tex = vec4(0.0);
		return;
	}

	if (!has_indirect) {
		stage_tex = apply_swap_table(
			sample_texture_unit_with_grad(texmap, original_norm, dFdx(original_norm), dFdy(original_norm)),
			stages[stage].tex_swap_table_index
		);
		return;
	}

	vec2 final_norm = texel_to_normalized(texmap, final_texel);
	stage_tex = apply_swap_table(
		sample_texture_unit_with_grad(texmap, final_norm, dFdx(indirect_ops[stage].utc_lod != 0 ? original_norm : final_norm), dFdy(indirect_ops[stage].utc_lod != 0 ? original_norm : final_norm)),
		stages[stage].tex_swap_table_index
	);
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
		case 0x1C: return k0.aaa;
		case 0x1D: return k1.aaa;
		case 0x1E: return k2.aaa;
		case 0x1F: return k3.aaa;
		default:   return vec3(0.0);
	}
}

bool alpha_compare(float alpha, int comp, int ref) {
	float ref_float = float(ref) / 255.0;
	switch (comp) {
		case 0: return false;
		case 1: return alpha < ref_float;
		case 2: return alpha == ref_float;
		case 3: return alpha <= ref_float;
		case 4: return alpha > ref_float;
		case 5: return alpha != ref_float;
		case 6: return alpha >= ref_float;
		case 7: return true;
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

vec3 get_parameter_for_color_stage(int idx, int stage, vec4 stage_tex, vec4 stage_ras) {
	switch (idx) {
		case 0: return color_regs[0].rgb;
		case 1: return color_regs[0].aaa;
		case 2: return color_regs[1].rgb;
		case 3: return color_regs[1].aaa;
		case 4: return color_regs[2].rgb;
		case 5: return color_regs[2].aaa;
		case 6: return color_regs[3].rgb;
		case 7: return color_regs[3].aaa;
		case 8: return stage_tex.rgb;
		case 9: return stage_tex.aaa;
		case 10: return stage_ras.rgb;
		case 11: return stage_ras.aaa;
		case 12: return vec3(1.0, 1.0, 1.0);
		case 13: return vec3(0.5, 0.5, 0.5);
		case 14: return resolve_kcsel(stages[stage].kcsel);
		case 15: return vec3(0.0, 0.0, 0.0);
	}
}

vec3 get_parameter_for_alfa_stage(int idx, int stage, vec4 stage_tex, vec4 stage_ras) {
	switch (idx) {
		case 0: return color_regs[0].aaa; // ??????????  http://www.amnoid.de/gc/tev.html
		case 1: return color_regs[1].aaa;
		case 2: return color_regs[2].aaa;
		case 3: return color_regs[3].aaa;
		case 4: return stage_tex.aaa;
		case 5: return stage_ras.aaa;
		case 6: return resolve_kasel(stages[stage].kasel);
		case 7: return vec3(0.0);
	}
}

float read_ztexture(vec4 last_tex) {
	// weird dolphin voodoo magic
	switch (ztexture_fmt) {
		case 0: return dot(last_tex, vec4(0, 0, 0, 1));
		case 1: return dot(last_tex, vec4(1, 0, 0, 256));
		case 2: return dot(last_tex, vec4(65536, 256, 1, 0));
	}

	return 0.0; // should never happen but ok
}

  vec3 dickhead_operation_ivec3(vec3 innie) {

	vec3 x = abs(innie);
  	vec3 f = fract(x);
  	return f + step(vec3(1.0), x) * (vec3(1.0) - ceil(f));
  }

  float dickhead_operation_float(float innie) {
	float x = abs(innie);
  	float f = fract(x);
  	return f + step(1.0, x) * (1.0 - ceil(f));
  }

void main(void) {
	vec3 last_color_dest;
	float last_alfa_dest;
	vec2 previous_stage_texel = vec2(0.0);
	vec4 last_tex_sample = vec4(0.0);

	color_regs[0] = reg0;
	color_regs[1] = reg1;
	color_regs[2] = reg2;
	color_regs[3] = reg3;

	for (int i = 0; i < num_tev_stages; i++) {
		vec4 stage_tex;
		vec2 stage_final_texel;
		float bump_alpha_plain;
		float bump_alpha_normalized;
		compute_stage_texture_info(i, previous_stage_texel, stage_tex, stage_final_texel, bump_alpha_plain, bump_alpha_normalized);
		vec4 stage_ras = get_color_from_ras_channel_id(stages[i].ras_channel_id, i, bump_alpha_plain, bump_alpha_normalized);

		vec3 ca = dickhead_operation_ivec3(get_parameter_for_color_stage(stages[i].in_color_a, i, stage_tex, stage_ras));
		vec3 cb = dickhead_operation_ivec3(get_parameter_for_color_stage(stages[i].in_color_b, i, stage_tex, stage_ras));
		vec3 cc = dickhead_operation_ivec3(get_parameter_for_color_stage(stages[i].in_color_c, i, stage_tex, stage_ras));
		vec3 cd = get_parameter_for_color_stage(stages[i].in_color_d, i, stage_tex, stage_ras);
		vec3 aa = dickhead_operation_ivec3(get_parameter_for_alfa_stage(stages[i].in_alfa_a,   i, stage_tex, stage_ras));
		vec3 ab = dickhead_operation_ivec3(get_parameter_for_alfa_stage(stages[i].in_alfa_b,   i, stage_tex, stage_ras));
		vec3 ac = dickhead_operation_ivec3(get_parameter_for_alfa_stage(stages[i].in_alfa_c,   i, stage_tex, stage_ras));
		vec3 ad = get_parameter_for_alfa_stage(stages[i].in_alfa_d,   i, stage_tex, stage_ras);

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
		} else if (stages[i].color_op == 1) {
			last_color_dest = (cd - ((1 - cc) * ca + cc * cb) + vec3(stages[i].bias_color)) * vec3(stages[i].scale_color);
		} else {
			last_color_dest = (cd + ((1 - cc) * ca + cc * cb) + vec3(stages[i].bias_color)) * vec3(stages[i].scale_color);
		}

		if (stages[i].alfa_op >= 8) {
			uint a_r = uint(round(aa.r * 255.0));
			uint b_r = uint(round(ab.r * 255.0));
			int op = stages[i].alfa_op;
			bool cond = (op & 1) == 0 ? (a_r > b_r) : (a_r == b_r);
			last_alfa_dest = (cond ? ac : ad).r;
		} else if (stages[i].alfa_op == 1) {
			last_alfa_dest = ((ad - ((1 - ac) * aa + ac * ab) + vec3(stages[i].bias_alfa)) * vec3(stages[i].scale_alfa)).x;
		} else {
			last_alfa_dest = ((ad + ((1 - ac) * aa + ac * ab) + vec3(stages[i].bias_alfa)) * vec3(stages[i].scale_alfa)).x;
		}

		if (stages[i].clamp_color != 0) {
			last_color_dest = clamp(last_color_dest, 0.0, 1.0);
		}
		
		if (stages[i].clamp_alfa != 0) {
			last_alfa_dest = clamp(last_alfa_dest, 0.0, 1.0);
		}


		// dolphin does this shit and so will i
		// last_color_dest = dickhead_operation_ivec3(last_color_dest);
		// last_alfa_dest = dickhead_operation_float(last_alfa_dest);
		
		color_regs[stages[i].color_dest].rgb = last_color_dest;
		color_regs[stages[i].alfa_dest].a = last_alfa_dest;
		previous_stage_texel = stage_final_texel;
		last_tex_sample = stage_tex;
	}

	// last_alfa_dest = 1;
#if ALPHA_TEST_ENABLED
	bool alpha_test0 = alpha_compare(last_alfa_dest, alpha_comp0, alpha_ref0);
	bool alpha_test1 = alpha_compare(last_alfa_dest, alpha_comp1, alpha_ref1);

	bool alpha_pass;
	switch (alpha_aop) {
		case 0: alpha_pass = alpha_test0 && alpha_test1; break;
		case 1: alpha_pass = alpha_test0 || alpha_test1; break;
		case 2: alpha_pass = alpha_test0 != alpha_test1; break;
		case 3: alpha_pass = alpha_test0 == alpha_test1; break;
	}

	if (!alpha_pass) {
		discard;
	}
#endif

#if BBOX_ENABLED
	uint scale = uint(max(u_efb_scale, 1));
	uint px = (uint(gl_FragCoord.x) / scale) & 0x3FEu;
	uint py = (527u - (uint(gl_FragCoord.y) / scale)) & 0x3FEu;
	atomicMin(bbox_left, px);
	atomicMax(bbox_right, px | 1u);
	atomicMin(bbox_top, py);
	atomicMax(bbox_bottom, py | 1u);
#endif

	out_Color0 = vec4(last_color_dest, is_alpha_forced != 0 ? forced_alpha / 255 : last_alfa_dest);
	out_Color1 = vec4(0, 0, 0, last_alfa_dest);

#if ZTEXTURE_ENABLED || 1
	if (ztexture_op != 0) {
		float ztexture = read_ztexture(last_tex_sample);

		ztexture += zbias;

		if (ztexture_op == 1) {
			ztexture += gl_FragCoord.z;
		}

		gl_FragDepth = ztexture;
	} else {
		gl_FragDepth = gl_FragCoord.z;
	}
#endif

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
