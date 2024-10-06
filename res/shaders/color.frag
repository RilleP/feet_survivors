
in highp vec3 v_color;
in highp vec2 v_uv;
in highp vec3 v_normal;

uniform highp vec3 scale_color;

out highp vec4 color; 


void main() {
	highp vec3 sun_dir = normalize(vec3(1, 1, -3));

	highp float light = -dot(sun_dir, normalize(v_normal)) + 0.5;

	color.rgb = v_color * vec3(light) * scale_color;
	//color.rgb = normalize(v_normal);
	//color.rgb = vec3(v_uv.x, v_uv.y, 0);
	color.a = 1.0;
	color.rgb *= color.a;
}