#version 130

in  vec3 in_Position;

out vec2 UV;
uniform mat4 MVP;

void main(void) {
	gl_Position = MVP * vec4(in_Position, -1.0);
	UV = vec2(-gl_Position.y / 2 + 0.5, gl_Position.x / 2 + 0.5);
}