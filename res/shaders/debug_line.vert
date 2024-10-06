
layout(location = 0) in vec3 position;
layout(location = 1) in vec4 color;

uniform mat4 view_projection;

out vec4 o_color;

void main() {
	o_color = color;
	gl_Position = view_projection * vec4(position, 1);
}