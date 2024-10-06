package main

import "core:math"
import "core:math/rand"
import GL "../packages/wasm/WebGL"


Particle :: struct {
	p: Vec3,
	size: f32,
	dir: Vec3,
	speed: f32,
	color: Vec4,
	time_remaining: f32,
}

Particle_System :: struct {
	particles: []Particle,
	vertices: []Particle_Vertex,
	first_index: int,
	count: int,

	vbo, index_buffer: GL_Buffer,
}

add_particle :: proc(ps: ^Particle_System, p: Particle) {
	if ps.count < len(ps.particles) {
		index := (ps.first_index + ps.count) % len(ps.particles);
		ps.particles[index] = p;

		ps.count += 1;
	}
}

Particle_Vertex :: struct {
	p: Vec3,
	uv: Vec2,
	color: Vec4,
}

create_particle_system :: proc(max_count: int) -> Particle_System {
	system: Particle_System;
	system.particles = make([]Particle, max_count);
	system.vbo = GL.CreateBuffer();
	GL.BindBuffer(GL.ARRAY_BUFFER, system.vbo);
	GL.BufferData(GL.ARRAY_BUFFER, max_count * size_of(Particle_Vertex) * 4, nil, GL.DYNAMIC_DRAW);

	system.vertices = make([]Particle_Vertex, max_count*4);

	system.index_buffer = GL.CreateBuffer();
	GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, system.index_buffer);
	assert(max_count * 4 < int(max(u16)));
	indices := make([]u16, max_count * 6);
	{
		first_vertex := u16(0);
		for ii := 0; ii < len(indices); ii += 6 {
			indices[ii+0] = first_vertex+0;
			indices[ii+1] = first_vertex+1;
			indices[ii+2] = first_vertex+2;

			indices[ii+3] = first_vertex+0;
			indices[ii+4] = first_vertex+2;
			indices[ii+5] = first_vertex+3;

			first_vertex += 4;
		}
	}
	GL.BufferData(GL.ELEMENT_ARRAY_BUFFER, size_of(u16) * len(indices), &indices[0], GL.STATIC_DRAW);
	delete(indices);

	/*center := Vec3{40, 40, 1};
	radius := f32(100);
	for ii in 0..<max_count {
		add_particle(&system, {
			p = center + {rand.float32_range(-radius, radius), rand.float32_range(-radius, radius), 0},
			size = 2,
			color = {0, 1, 0, 1},
			dir = {rand.float32(), rand.float32(), 0},
			speed = rand.float32()*5,
			time_remaining = rand.float32()*3,
		});
	}*/

	return system;
}

Range :: struct {
	min, roof: int,
}

get_active_particle_ranges :: proc(ps: ^Particle_System) -> (ranges: [2]Range) {
	roof := ps.first_index + ps.count;
	ranges[0].min = ps.first_index;
	if roof > len(ps.particles) {
		ranges[0].roof = len(ps.particles);

		ranges[1].min = 0;
		ranges[1].roof = roof - len(ps.particles);
	}
	else {
		ranges[0].roof = roof;
	}
	return;
}

draw_particle_system :: proc(ps: ^Particle_System) {
	shader := particle_shader;
	set_shader(shader);

	set_texture(&blood_mask);

	GL.Enable(GL.BLEND);
	GL.DepthMask(false);


	camera_view_projection := get_view_projection_3d();
	GL.UniformMatrix4fv(GL.GetUniformLocation(shader, "view_projection"), camera_view_projection);

	GL.BindBuffer(GL.ARRAY_BUFFER, ps.vbo);

	ranges := get_active_particle_ranges(ps);
	added_verts := 0;
	added_indices := 0;
	for range in ranges {
		for ii in range.min..<range.roof {
			p := &ps.particles[ii];
			p.p += p.dir * p.speed * dt;
			p.speed -= math.min((p.speed+25) * dt, p.speed);
			p.time_remaining -= dt;
			if p.time_remaining < 0 {
				if ii == ps.first_index {
					ps.count -= 1;
					ps.first_index += 1;
					if ps.first_index == len(ps.particles) {
						ps.first_index = 0;
					}
				}	
				continue;
			}

			FADE_OUT_DURATION :: 0.1;

			c := p.p;

			color := p.color;
			if p.time_remaining < FADE_OUT_DURATION {
				color.a = p.time_remaining / FADE_OUT_DURATION;
			}

			r := p.size*0.5;

			ps.vertices[added_verts+0] = {
				p = c + {-r, -r, 0},
				color = color,
				uv = {0, 0},
			}
			ps.vertices[added_verts+1] = {
				p = c + {+r, -r, 0},
				color = color,
				uv = {1, 0},
			}
			ps.vertices[added_verts+2] = {
				p = c + {+r, +r, 0},
				color = color,
				uv = {1, 1},
			}
			ps.vertices[added_verts+3] = {
				p = c + {-r, +r, 0},
				color = color,
				uv = {0, 1},
			}
			added_verts += 4;
			added_indices += 6;
		}
	}

	GL.BufferSubData(GL.ARRAY_BUFFER, 0, size_of(Particle_Vertex)*added_verts, &ps.vertices[0]);
	GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, ps.index_buffer);

	GL.EnableVertexAttribArray(0);
	GL.VertexAttribPointer(0, 3, GL.FLOAT, false, size_of(Particle_Vertex), offset_of(Particle_Vertex, p));

	GL.EnableVertexAttribArray(1);
	GL.VertexAttribPointer(1, 4, GL.FLOAT, false, size_of(Particle_Vertex), offset_of(Particle_Vertex, color));

	GL.EnableVertexAttribArray(2);
	GL.VertexAttribPointer(2, 2, GL.FLOAT, false, size_of(Particle_Vertex), offset_of(Particle_Vertex, uv));

	GL.DrawElements(GL.TRIANGLES, added_indices, GL.UNSIGNED_SHORT, nil);
}

