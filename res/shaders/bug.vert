
layout(location = 0) in highp vec3 position;
layout(location = 2) in vec2 uv;
layout(location = 4) in vec3 normal;
layout(location = 6) in vec3 color;

/*uniform InstanceData {
	
} instances;*/
uniform vec4 data[1000];

//uniform mat4 transform;
uniform mat4 camera_view;
uniform mat4 camera_proj;

out vec3 v_color;
out vec2 v_uv;
out vec3 v_normal;

void main() {
	vec4 instance = data[gl_InstanceID];
	highp float c = cos(instance.z);
	highp float s = sin(instance.z);
	highp mat4 transform = mat4(c, s, 0, 0, 
						  s, -c, 0, 0,
						  0, 0, 1, 0,
						  instance.x, instance.y, 0, 1);

	highp vec3 p = position;
	p.y += color.b * cos(instance.w*15.0) * 0.1;
	p.y += color.r * sin(instance.w*15.0) * 0.1;
	gl_Position = camera_proj * camera_view * transform * vec4(p, 1);
	v_normal = normalize(normal);
	v_color = vec3(0.1);
	v_uv = uv;
}