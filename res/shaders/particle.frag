
in highp vec4 v_color;
in highp vec2 v_uv;

uniform sampler2D tex_col0;

out highp vec4 color;


void main() {
	highp vec4 col1 = texture(tex_col0, v_uv);
	//color = col1 * v_color;
	color = v_color;
	color.a *= col1.r;
	color.rgb *= color.a;
}