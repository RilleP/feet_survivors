
layout(location = 0) in highp vec3 position;
layout(location = 2) in vec2 uv;
layout(location = 4) in vec3 normal;
layout(location = 6) in vec3 color;

uniform mat4 transform;
uniform mat4 camera_view;
uniform mat4 camera_proj;

out vec3 v_color;
out vec2 v_uv;
out vec3 v_normal;

void main() {
	gl_Position = camera_proj * camera_view * transform * vec4(position, 1);
	v_normal = normalize(normal);
	v_color = color;
	v_uv = uv;
}