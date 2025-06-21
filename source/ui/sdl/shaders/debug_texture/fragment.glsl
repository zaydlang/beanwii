#version 330 core

in vec2 UV;
out vec4 out_Color;

uniform sampler2D wiiscreen;

void main() {
    out_Color = texture(wiiscreen, UV);
}