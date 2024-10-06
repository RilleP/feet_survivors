package main

import "core:math"

bug_shader: Shader;
color_shader: Shader;
textured_shader: Shader;
debug_line_shader: Shader;
text_shader: Shader;
color_2d_shader: Shader;
particle_shader: Shader;

current_shader: Shader;
current_texture: ^Texture;

font: Font;

compute_font_size :: proc() -> f32 {
	if window_height < window_width {
		return f32(int(f32(window_height)/900 * 50));	
	}
	else {
		return math.min(f32(int(f32(window_height)/900 * 50)), f32(int(f32(window_width)/750 * 50)));
	}
}

Align_X :: enum {
	Left,
	Center,
	Right,
};

Align_Y :: enum {
	Top,
	Center,
	Bottom,
}

draw_text :: proc(text: string, font: ^Font, position: Vec2, align_x: Align_X, align_y: Align_Y, color: Vec4, bounds: ^Rect = nil) {
	size := get_text_draw_size(text, font);

	p: Vec2;
	switch align_x {
		case .Left: p.x = position.x;
		case .Center: p.x = position.x - size.x*0.5;
		case .Right: p.x = position.x - size.x;
	}
	switch align_y {
		case .Top: p.y = position.y + size.y;
		case .Center: p.y = position.y + size.y*0.5;
		case .Bottom: p.y = position.y;
	}
	maybe_draw_text(text, font, p + {2, 2}, {0, 0, 0, 1}, true, bounds);
	maybe_draw_text(text, font, p, color, true, bounds);
}

get_text_bounds :: proc(text: string, font: ^Font, position: Vec2, bounds: ^Rect = nil) {
	maybe_draw_text(text, font, position, {}, false, bounds);
}

get_text_draw_size :: proc(text: string, font: ^Font) -> Vec2 {
	bounds: Rect;
	maybe_draw_text(text, font, 0, {}, false, &bounds);
	return bounds.size;
}

draw_char :: proc(c: int, font: ^Font, position: Vec2, color: Vec4) {
	glyph : ^GlyphInfo;

	if(c < font.first_char || c > font.last_char) {
		glyph = &font.glyphs[0];
	}
	else {
		glyph = &font.glyphs[c - font.first_char];
	}


	draw_rect_min_size(position+glyph.offset, glyph.size, color, glyph.uv_min, glyph.uv_max);
}

Vertex_2d :: struct {
	position : Vec2,
	color    : Vec4,
	uv       : Vec2,
}

BATCH_TRI_CAP :: 1000;
vertex_data_2d : [BATCH_TRI_CAP*3]Vertex_2d;
batch_vertex_count_2d : i32 = 0;


draw_quad_corners :: proc(p0, p1, p2, p3: Vec2, uv0, uv1, uv2, uv3: Vec2, color: Vec4) #no_bounds_check {
	if(batch_vertex_count_2d+6 > BATCH_TRI_CAP) {
		flush_batch_2d()
	}

	vertex_data_2d[batch_vertex_count_2d+0] = {p0, color, uv0};
	vertex_data_2d[batch_vertex_count_2d+1] = {p1, color, uv1};
	vertex_data_2d[batch_vertex_count_2d+2] = {p2, color, uv2};

	vertex_data_2d[batch_vertex_count_2d+3] = {p0, color, uv0};
	vertex_data_2d[batch_vertex_count_2d+4] = {p2, color, uv2};
	vertex_data_2d[batch_vertex_count_2d+5] = {p3, color, uv3};
	batch_vertex_count_2d += 6;
}


draw_rect_min_max :: #force_inline proc(min, max: Vec2, color: Vec4, min_uv := Vec2{0, 0}, max_uv := Vec2{1, 1}) {
	draw_quad_corners(min, {max.x, min.y}, max, {min.x, max.y}, min_uv, {max_uv.x, min_uv.y}, max_uv, {min_uv.x, max_uv.y}, color);
}
draw_rect_min_size :: #force_inline proc(min, size: Vec2, color: Vec4, min_uv := Vec2{0, 0}, max_uv := Vec2{1, 1}) {

	draw_rect_min_max(min, min+size, color, min_uv, max_uv);
}

draw_colored_rect_min_max :: #force_inline proc(min, max: Vec2, color: Vec4) {
	set_shader(color_2d_shader);
	set_texture(nil);

	draw_rect_min_max(min, max, color);
}

draw_colored_rect_min_size :: #force_inline proc(min, size: Vec2, color: Vec4) {
	draw_colored_rect_min_max(min, min+size, color);
}

start_drawing_text :: #force_inline proc(font: ^Font) {
	set_shader(text_shader);
	set_texture(&font.texture);
}

maybe_draw_text :: proc(text: string, font: ^Font, position: Vec2, color: Vec4, draw: bool, bounds: ^Rect = nil) {
	cursor := position;
	if(draw) {
		start_drawing_text(font);
	}

	bmin := position;
	bmax := position;
	for r in text {
		c := cast(int)r;
		
		xadvance : f32;
		glyph : ^GlyphInfo;
		if(c == '\t') {
			xadvance = font.space_xadvance * 4;
		}
		else if(c == ' ') {
			xadvance = font.space_xadvance;	
		}
		else {
			if(c < font.first_char || c > font.last_char) {
				glyph = &font.glyphs[0];
			}
			else {
				glyph = &font.glyphs[c - font.first_char];
			}
			xadvance = glyph.xadvance;
		}


		if(glyph != nil) {
			p := cursor + glyph.offset;

			bmax.x = p.x + glyph.size.x;
			bmax.y = max(p.y + glyph.size.y, bmax.y);
			bmin.y = min(p.y, bmin.y);

			if(draw) {
				draw_rect_min_size(p, glyph.size, color, glyph.uv_min, glyph.uv_max);				
			}
		}
		cursor.x += xadvance;
		bmax.x = cursor.x;
	}

	if(bounds != nil) {
		bmax.x = cursor.x;
		bounds.min = bmin;
		bounds.size = bmax-bmin;
	}
}

Debug_Vertex :: struct {
	p: Vec3,
	c: Vec4,
}

MAX_DEBUG_LINES :: 10000;
MAX_DEBUG_LINE_VERTICES :: MAX_DEBUG_LINES*2;
debug_line_vertices: [MAX_DEBUG_LINE_VERTICES]Debug_Vertex;
debug_line_vertex_count: int;

debug_ray :: proc(p0, v: Vec3, c: Vec4) {
	debug_line(p0, p0+v, c);
}
debug_line :: proc(a, b: Vec3, c: Vec4) {
	if debug_line_vertex_count+2 > MAX_DEBUG_LINE_VERTICES {
		return;
	}

	debug_line_vertices[debug_line_vertex_count+0] = {a, c};
	debug_line_vertices[debug_line_vertex_count+1] = {b, c};

	debug_line_vertex_count += 2;
}

debug_horizontal_rect :: proc(rect: Rect, z: f32, color: Vec4, transform: Matrix4) {
	min := rect.min;
	max := rect.min + rect.size;
	a := transform_point(Vec3{min.x, min.y, z}, transform);
    b := transform_point(Vec3{min.x, max.y, z}, transform);
    c := transform_point(Vec3{max.x, max.y, z}, transform);
    d := transform_point(Vec3{max.x, min.y, z}, transform);

    debug_line(a, b, color);
    debug_line(b, c, color);
    debug_line(c, d, color);
    debug_line(d, a, color);
}

debug_cube_centered :: proc(center, size: Vec3, color: Vec4) {
	debug_cube(center - size*0.5, center + size*0.5, color);
}
debug_cube :: proc(min, max: Vec3, color: Vec4) {
	a := Vec3{min.x, min.y, min.z};
    b := Vec3{max.x, min.y, min.z};
    c := Vec3{min.x, max.y, min.z};
    d := Vec3{max.x, max.y, min.z};

    e := Vec3{min.x, min.y, max.z};
    f := Vec3{max.x, min.y, max.z};
    g := Vec3{min.x, max.y, max.z};
    h := Vec3{max.x, max.y, max.z};

    /**
     *     
     *          E-----F
     *         /|    /|
     * MIN -> A-----B |
     *        | G---|-H <- MAX
     *        |/    |/
     *        C-----D
     * 
     * */

    debug_line(a, b, color);
    debug_line(a, c, color);
    debug_line(c, d, color);
    debug_line(b, d, color);

    debug_line(e, f, color);
    debug_line(e, g, color);
    debug_line(g, h, color);
    debug_line(f, h, color);

    debug_line(a, e, color);
    debug_line(b, f, color);
    debug_line(c, g, color);
    debug_line(d, h, color);
}

debug_cube_transformed :: proc(min, max: Vec3, color: Vec4, transform: Matrix4) {
	a := transform_point(Vec3{min.x, min.y, min.z}, transform);
    b := transform_point(Vec3{max.x, min.y, min.z}, transform);
    c := transform_point(Vec3{min.x, max.y, min.z}, transform);
    d := transform_point(Vec3{max.x, max.y, min.z}, transform);

    e := transform_point(Vec3{min.x, min.y, max.z}, transform);
    f := transform_point(Vec3{max.x, min.y, max.z}, transform);
    g := transform_point(Vec3{min.x, max.y, max.z}, transform);
    h := transform_point(Vec3{max.x, max.y, max.z}, transform);

    /**
     *     
     *          E-----F
     *         /|    /|
     * MIN -> A-----B |
     *        | G---|-H <- MAX
     *        |/    |/
     *        C-----D
     * 
     * */

    debug_line(a, b, color);
    debug_line(a, c, color);
    debug_line(c, d, color);
    debug_line(b, d, color);

    debug_line(e, f, color);
    debug_line(e, g, color);
    debug_line(g, h, color);
    debug_line(f, h, color);

    debug_line(a, e, color);
    debug_line(b, f, color);
    debug_line(c, g, color);
    debug_line(d, h, color);
}