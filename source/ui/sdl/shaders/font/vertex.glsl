#version 330 core

uniform mat4 MVP;
in vec2 in_Position;
in vec2 in_UV;

out vec2 UV;

void main() {
    gl_Position = MVP * vec4(in_Position, 0, 1);
    UV = in_UV;
}