#version 130

in  vec3 in_Position;

in vec2 texcoord;
in vec4 in_color;

out vec2 UV;
out vec4 frag_color;

uniform mat4x3 position_matrix;
uniform mat4x3 texture_matrix;
uniform mat4 MVP;

void main(void) {
	gl_Position = MVP * vec4(position_matrix * vec4(in_Position, 1.0), 1.0);
		// gl_Position.x = gl_Position.x / gl_Position.w;
		// gl_Position.y = gl_Position.y / gl_Position.w;
		// gl_Position.z = gl_Position.z / gl_Position.w;

		// gl_Position.y = -gl_Position.y;
		// gl_Position.x = -gl_Position.z;
	
	UV = (texture_matrix * vec4(texcoord, 1.0, 1.0)).xy;
	frag_color = in_color;
}