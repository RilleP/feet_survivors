package main

import "core:fmt"
import "core:math/linalg"
import "core:slice"
import GL "../packages/wasm/WebGL"

Shader :: GL.Program;
GL_Buffer :: GL.Buffer;

compile_shader :: proc(source: string, type: GL.Enum) -> GL.Shader {
	
	SOURCE_INTRO :: 
	`#version 300 es
	`;
	
	result := GL.CreateShader(type);
	GL.ShaderSource(result, {SOURCE_INTRO, source});
	GL.CompileShader(result);
	info_buf: [512]byte;
	vertex_error := GL.GetShaderInfoLog(result, info_buf[:]);
	if(len(vertex_error) > 0) {
		fmt.printf("Failed to compile shader %s\n", source);
		fmt.printf(vertex_error);
		return 0;
	}
	return result;
}

compile_shader_from_file :: proc($file_path: string, type: GL.Enum) -> GL.Shader {
	SRC :: #load(file_path, string);
	return compile_shader(SRC, type);
}

create_and_link_program :: proc(vertex_shader, fragment_shader: GL.Shader) -> GL.Program {
	result := GL.CreateProgram();
	GL.AttachShader(result, vertex_shader);
	GL.AttachShader(result, fragment_shader);
	GL.LinkProgram(result);
	info_buf: [512]byte;
	program_error := GL.GetProgramInfoLog(result, info_buf[:]);
	if len(program_error) > 0 {
		log("Failed to link shader program\n");
		log(program_error);
		assert(false);
		return 0;
	}
	return result;
}

init_draw :: proc() {
	font = {
	}
	vertex_shader := compile_shader_from_file("../res/shaders/basic.vert", GL.VERTEX_SHADER);
	defer GL.DeleteShader(vertex_shader);

	bug_vertex_shader := compile_shader_from_file("../res/shaders/bug.vert", GL.VERTEX_SHADER);
	defer GL.DeleteShader(bug_vertex_shader);
	
	colored_fragment_shader := compile_shader_from_file("../res/shaders/color.frag", GL.FRAGMENT_SHADER);
	defer GL.DeleteShader(colored_fragment_shader);
	color_shader = create_and_link_program(vertex_shader, colored_fragment_shader);	
	bug_shader = create_and_link_program(bug_vertex_shader, colored_fragment_shader);
	
	textured_fragment_shader := compile_shader_from_file("../res/shaders/textured.frag", GL.FRAGMENT_SHADER);
	defer GL.DeleteShader(textured_fragment_shader);
	textured_shader = create_and_link_program(vertex_shader, textured_fragment_shader);

	debug_line_vertex_shader := compile_shader_from_file("../res/shaders/debug_line.vert", GL.VERTEX_SHADER);
	defer GL.DeleteShader(debug_line_vertex_shader);

	debug_line_fragment_shader := compile_shader_from_file("../res/shaders/debug_line.frag", GL.FRAGMENT_SHADER);
	defer GL.DeleteShader(debug_line_fragment_shader);

	debug_line_shader = create_and_link_program(debug_line_vertex_shader, debug_line_fragment_shader);

	vertex_shader_2d := compile_shader_from_file("../res/shaders/basic2d.vert", GL.VERTEX_SHADER);
	defer GL.DeleteShader(vertex_shader_2d);
	text_fragment_shader := compile_shader_from_file("../res/shaders/text_web.frag", GL.FRAGMENT_SHADER);
	defer GL.DeleteShader(text_fragment_shader);
	text_shader = create_and_link_program(vertex_shader_2d, text_fragment_shader);

	color_2d_fragment_shader := compile_shader_from_file("../res/shaders/color2d.frag", GL.FRAGMENT_SHADER);
	defer GL.DeleteShader(color_2d_fragment_shader);
	color_2d_shader = create_and_link_program(
		vertex_shader_2d, 
		color_2d_fragment_shader);

	particle_vertex_shader := compile_shader_from_file("../res/shaders/particle.vert", GL.VERTEX_SHADER);
	defer GL.DeleteShader(particle_vertex_shader);
	particle_fragment_shader := compile_shader_from_file("../res/shaders/particle.frag", GL.FRAGMENT_SHADER);
	defer GL.DeleteShader(particle_fragment_shader);
	particle_shader = create_and_link_program(particle_vertex_shader, particle_fragment_shader);

	batch_vbo = GL.CreateBuffer();
	GL.BindBuffer(GL.ARRAY_BUFFER, batch_vbo);
	GL.BufferData(GL.ARRAY_BUFFER, size_of(vertex_data_2d), nil, GL.DYNAMIC_DRAW);
}

set_shader :: proc(shader: Shader) {
	if current_shader != shader {
		current_shader = shader;
		GL.UseProgram(shader);
		flush_batch_2d()
	}
}

set_texture :: proc(texture: ^Texture) {
	if texture != current_texture {
		GL.BindTexture(GL.TEXTURE_2D, GL.Texture(texture.id));
		flush_batch_2d()
	}
}

set_camera_uniforms :: proc(_program: Shader, camera_view, camera_proj: Matrix4) {
	program := GL.Program(_program);
	GL.UseProgram(program);
	GL.UniformMatrix4fv(GL.GetUniformLocation(program, "camera_view"), camera_view);
	GL.UniformMatrix4fv(GL.GetUniformLocation(program, "camera_proj"), camera_proj);
}

frame_camera_view, frame_camera_proj: Matrix4;

get_view_projection_3d :: proc() -> Matrix4 {
	return frame_camera_proj*frame_camera_view;
}

start_draw_3d :: proc(camera_view, camera_proj: Matrix4) {
	frame_camera_view = camera_view;
	frame_camera_proj = camera_proj;
	set_camera_uniforms(color_shader, camera_view, camera_proj);
	set_camera_uniforms(textured_shader, camera_view, camera_proj);
	set_camera_uniforms(bug_shader, camera_view, camera_proj);

	GL.DepthMask(true);
	GL.Enable(GL.DEPTH_TEST);
	GL.Enable(GL.CULL_FACE);
	GL.FrontFace(GL.CCW);
	GL.Disable(GL.BLEND);
}

end_draw_3d :: proc() {
	flush_debug_lines();
}

frame_camera_view_proj2d: Matrix4;

set_camera_uniforms2d :: proc(_program: Shader, view_proj: Matrix4) {
	program := GL.Program(_program);
	GL.UseProgram(program);
	GL.UniformMatrix4fv(GL.GetUniformLocation(program, "view_projection"), view_proj);
}
start_draw_2d :: proc() {
	GL.DepthMask(false);
	GL.Disable(GL.DEPTH_TEST);
	GL.Disable(GL.CULL_FACE);
	GL.FrontFace(GL.CCW);
	GL.Enable(GL.BLEND);
	GL.BlendFunc(GL.ONE, GL.ONE_MINUS_SRC_ALPHA);

	current_shader = 0;
	current_texture = nil;

	camera_proj := linalg.matrix_ortho3d_f32(0, window_size.x, window_size.y, 0, 1, -1);
	set_camera_uniforms2d(text_shader, camera_proj);
	set_camera_uniforms2d(color_2d_shader, camera_proj);
}

end_draw_2d :: proc() {
	flush_batch_2d();
}

batch_vbo: GL.Buffer;
flush_batch_2d :: proc() {
	if batch_vertex_count_2d == 0 {
	 	return;	
	}

	GL.BindBuffer(GL.ARRAY_BUFFER, cast(GL.Buffer)batch_vbo);
	vertex_count := batch_vertex_count_2d;
	GL.BufferSubData(GL.ARRAY_BUFFER, 0, size_of(Vertex_2d)*cast(int)vertex_count, slice.as_ptr(vertex_data_2d[:vertex_count]));

	GL.EnableVertexAttribArray(0);
	GL.VertexAttribPointer(0, 2, GL.FLOAT, false, size_of(Vertex_2d), offset_of(Vertex_2d, position));

	GL.EnableVertexAttribArray(1);
	GL.VertexAttribPointer(1, 4, GL.FLOAT, false, size_of(Vertex_2d), offset_of(Vertex_2d, color));

	GL.EnableVertexAttribArray(2);
	GL.VertexAttribPointer(2, 2, GL.FLOAT, false, size_of(Vertex_2d), offset_of(Vertex_2d, uv));


	GL.DrawArrays(GL.TRIANGLES, 0, cast(int)vertex_count);
	batch_vertex_count_2d = 0;
}

start_draw_frame :: proc(bg: Vec3) {
	current_shader = 0;
	current_texture = nil;
	
	GL.Enable(GL.BLEND);
	GL.BlendFunc(GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
	GL.Disable(GL.CULL_FACE);

	GL.ClearColor(bg.x, bg.y, bg.z, 1);
	GL.Clear(GL.COLOR_BUFFER_BIT);
}


debug_line_vertex_buffer: GL.Buffer;

flush_debug_lines :: proc() {
	if debug_line_vertex_count == 0 {
		return;
	}
	defer debug_line_vertex_count = 0;

	if debug_line_vertex_buffer == 0 {
		debug_line_vertex_buffer = GL.CreateBuffer();
	}

	GL.BindBuffer(GL.ARRAY_BUFFER, debug_line_vertex_buffer);
	GL.BufferData(GL.ARRAY_BUFFER, size_of(Debug_Vertex) * debug_line_vertex_count, &debug_line_vertices[0], GL.DYNAMIC_DRAW);

	shader := debug_line_shader;
	set_shader(shader);

	camera_view_projection := get_view_projection_3d();
	GL.UniformMatrix4fv(GL.GetUniformLocation(shader, "view_projection"), camera_view_projection);

	GL.EnableVertexAttribArray(0);
	GL.VertexAttribPointer(0, 3, GL.FLOAT, false, size_of(Debug_Vertex), uintptr(0));

	GL.EnableVertexAttribArray(1);
    GL.VertexAttribPointer(1, 4, GL.FLOAT, false, size_of(Debug_Vertex), uintptr(size_of(Vec3)));

    GL.DrawArrays(GL.LINES, 0, debug_line_vertex_count);
}

end_draw_frame :: proc() {
	
}