#version 130

precision highp float; // needed only for version 1.30

out vec4 out_Color;

in vec2 UV;
uniform sampler2D wiiscreen;

void main(void) {
    // out_Color = vec4(1.0, 0.0, 0.0, 1.0);
	out_Color = vec4(texture(wiiscreen, UV).rgb, 1.0);
}