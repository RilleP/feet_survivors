
in highp vec4 v_color;
in highp vec2 v_uv;

out highp vec4 color; 

void main() {
	color = v_color;
	color.rgb *= color.a;
	color = vec4(1, 1, 1, 1);
}