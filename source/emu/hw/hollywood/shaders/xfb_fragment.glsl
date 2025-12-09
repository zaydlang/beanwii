#version 330 core

in vec2 v_texcoord;
out vec4 color;

uniform sampler2D u_texture;

void main() {
    color = texture(u_texture, vec2(v_texcoord.x, 1.0 - v_texcoord.y));
}