
in highp vec4 v_color;
in highp vec2 v_uv;

uniform sampler2D image;

out highp vec4 color; 

void main() {

	color = texture(image, v_uv).a * v_color;
	#if 0
	color.rgb = mix(vec3(1, 0, 1), color.rgb, color.a);
	color.a = 1.0;
	#else
	color.rgb *= color.a;
	#endif
}