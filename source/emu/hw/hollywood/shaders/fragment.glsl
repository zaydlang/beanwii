#version 140

out vec4 out_Color;

in vec2 UV;
in vec4 frag_color;
uniform sampler2D wiiscreen;

uniform TevConfig {
	uniform int num_tev_stages;
	uniform int in_color_a[16];
	uniform int in_color_b[16];
	uniform int in_color_c[16];
	uniform int in_color_d[16];
	uniform int in_alfa_a[16];
	uniform int in_alfa_b[16];
	uniform int in_alfa_c[16];
	uniform int in_alfa_d[16];
	uniform int color_dest[16];
	uniform int alfa_dest[16];
	uniform float bias_color[16];
	uniform float scale_color[16];
	uniform float bias_alfa[16];
	uniform float scale_alfa[16];
	uniform vec4 reg0;
	uniform vec4 reg1;
	uniform vec4 reg2;
	uniform vec4 reg3;
	uniform vec4 ras[16];
	uniform vec4 konst_a;
	uniform vec4 konst_b;
	uniform vec4 konst_c;
	uniform vec4 konst_d;
};

vec4 color_regs[4];

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
		case 8: return texture(wiiscreen, vec2(UV.y, UV.x)).rgb;
		case 9: return texture(wiiscreen, vec2(UV.y, UV.x)).aaa;
		case 10: return ras[stage].rgb;
		case 11: return ras[stage].aaa;
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
		case 4: return texture(wiiscreen, vec2(UV.y, UV.x)).aaa;
		case 5: return ras[stage].aaa;
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
		vec3 ca = get_parameter_for_color_stage(in_color_a[i], i, konst_a);
		vec3 cb = get_parameter_for_color_stage(in_color_b[i], i, konst_b);
		vec3 cc = get_parameter_for_color_stage(in_color_c[i], i, konst_c);
		vec3 cd = get_parameter_for_color_stage(in_color_d[i], i, konst_d);
		vec3 aa = get_parameter_for_alfa_stage(in_alfa_a[i],   i, konst_a);
		vec3 ab = get_parameter_for_alfa_stage(in_alfa_b[i],   i, konst_b);
		vec3 ac = get_parameter_for_alfa_stage(in_alfa_c[i],   i, konst_c);
		vec3 ad = get_parameter_for_alfa_stage(in_alfa_d[i],   i, konst_d);

		last_color_dest = (cd + ((1 - cc) * ca + cc * cb) + vec3(bias_color[i])) * vec3(scale_color[i]);
		last_alfa_dest = ((ad + ((1 - ac) * aa + ac * ab) + vec3(bias_alfa[i])) * vec3(scale_alfa[i])).x;

		color_regs[color_dest[i]].rgb = last_color_dest;
		color_regs[alfa_dest[i]].a = last_alfa_dest;
	}

	// last_alfa_dest = 1;
	out_Color = vec4(last_color_dest, last_alfa_dest);
	// out_Color = vec4(UV[0],UV[1],0,1);

	// if (in_alfa_a[0] == 7 && in_alfa_b[0] == 7 && in_alfa_c[0] == 7 && in_alfa_d[0] == 6) {
	// out_Color = vec4(1,0,0,1);
	// } else {
	// out_Color = vec4(0,1,0,last_alfa_dest);
	// }

	// out_Color = konst_a;
	// out_Color = texture(wiiscreen, vec2(UV.y, UV.x));

	// if (num_tev_stages == 1) {
		// out_Color = vec4(1.0, 0.0, 0.0, 1.0);
	// } else {
		// out_Color = vec4(0.0, 1.0, 0.0, 1.0);
	// }
}