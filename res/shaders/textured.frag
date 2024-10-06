
in highp vec3 v_color;
in highp vec2 v_uv;
in highp vec3 v_normal;

uniform sampler2D image;

uniform highp vec3 scale_color;
uniform bool use_scale_color;
uniform bool use_light;

out highp vec4 color; 

void main() {
	highp vec4 albedo = texture(image, v_uv);
	color.rgb = albedo.rgb;
	if (use_light) 
	{
		highp vec3 sun_dir = normalize(vec3(1.0, 1.0, -3.0));

		highp float light = -dot(sun_dir, normalize(v_normal)) + 0.5;

		color.rgb *= vec3(light);
	}

	if (use_scale_color) {
		color.rgb *= scale_color * v_color;
	}

	color.a = 1.0;
	//color.rgb *= v_color;
	//color.rgb *= color.a;
}