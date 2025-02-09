#version 330 core

uniform vec4 color;
uniform sampler2D font;

in vec2 UV;
out vec4 out_Color;

void main() {
    out_Color = texture(font, UV).r * color;
}