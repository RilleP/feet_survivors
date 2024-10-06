
layout(location = 0) in vec3 position;
layout(location = 1) in vec4 color;
layout(location = 2) in vec2 uv;

uniform mat4 view_projection;

out vec4 v_color;
out vec2 v_uv;

void main() {
	gl_Position = view_projection * vec4(position, 1);
	v_color = color;
	v_uv = uv;
}