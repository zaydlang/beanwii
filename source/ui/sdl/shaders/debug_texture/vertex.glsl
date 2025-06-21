#version 330 core

in vec3 in_Position;
in vec2 texcoord;

out vec2 UV;

void main() {
    gl_Position = vec4(in_Position, 1);
    UV = texcoord;
}