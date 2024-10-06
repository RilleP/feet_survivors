package main

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:fmt"
import "core:mem"

import GL "../packages/wasm/WebGL"

Vec2 :: [2]f32;
Vec3 :: [3]f32;
Vec4 :: [4]f32;
Vec2i :: [2]i32;
Matrix4 :: linalg.Matrix4f32;

File_Data :: struct {
	memory: []u8,
	count: int,
}

window_width: i32;
window_height: i32;
window_size: Vec2;

MAX_DT :: 1.0 / 10.0;
dt: f32;
draw_time: f32 = 0.0;
mouse_window_p: Vec2i;
mouse_p, last_mouse_p, mouse_delta: Vec2;
mouse_ui: Vec2;
mouse_scroll_amount: i32;
left_mouse_is_down: bool;
left_mouse_got_pressed: bool;
left_mouse_got_released: bool;
right_mouse_is_down: bool;
right_mouse_got_pressed: bool;
right_mouse_got_released: bool;

touch_down_p: Vec2;
touch_delta_p: Vec2;
is_dragging: bool;
is_touch_screen: bool;

ctrl_is_down: bool;
shift_is_down: bool;

inputted_text_buffer: [256]u8;
inputted_text_count: int;
enter_got_pressed: bool;
enter_is_pressed: bool; 


Direction :: enum {
	EAST,
	NORTH,
	WEST,
	SOUTH,
}

direction_input_is_down: [Direction][2]bool;
handle_move_key_event :: proc(pressed: bool, repeat: bool, secondary: bool, direction: Direction) {
	direction_input_is_down[direction][int(secondary)] = pressed;
}

blood_particle_system: Particle_System;
app: App;
App :: struct {
	is_touch_device: bool,
	enable_sound: bool,
	game: Game,
	sound_volume: f32,
}
app_init :: proc() {
	app.sound_volume = 0.5;

	blood_particle_system = create_particle_system(1000);

	for &speed in tile_part_fall_speed {
		speed = rand.float32_range(0.7, 1.7);
	}

	creature_instance_buffer = GL.CreateBuffer();
	GL.BindBuffer(GL.UNIFORM_BUFFER, creature_instance_buffer);
	GL.BufferData(GL.UNIFORM_BUFFER, size_of(creature_instance_data), &creature_instance_data[0], GL.DYNAMIC_DRAW);

	game_init(&app.game);
}

LEFT :: 0;
RIGHT :: 1;
FOOT_COUNT :: 2;

FOOT_MOUSE_COLLIDER_MIN := Vec3{-2, -1.8, 0.0};
FOOT_MOUSE_COLLIDER_MAX := Vec3{+2, +8.8, 2.0};

Foot :: struct {
	dead: bool,
	exploded: bool,
	size: f32,
	kills: int,
	bigger_stomp_remaining_time: f32,
	hp: int,
	grabbed_t: f32,
	position: Vec3,
	z_rotation: f32,
	mesh: ^Mesh,
	polygon: []Vec2, 
	polygon_bounds: Rect,

	time_since_last_stomp: f32,
}

foot_scale :: #force_inline proc(foot: Foot) -> f32 {
	return foot.size;
}

foot_transform :: proc(foot: Foot) -> Matrix4 {	
	transform := linalg.matrix4_translate_f32(foot.position);
	transform *= linalg.matrix4_rotate_f32(foot.z_rotation-math.PI*0.5, {0, 0, 1});
	transform *= linalg.matrix4_scale_f32(foot_scale(foot));
	return transform;
}

foot_transform_3d :: proc(foot: Foot, is_grabbed: bool) -> Matrix4 {
	transform := foot_transform(foot);
	z_offset: f32;
	
	if foot.grabbed_t > 0 {
		if is_grabbed {
			z_offset += inverse_cube(foot.grabbed_t);
		}
		else {
			z_offset += cube(foot.grabbed_t);
		}
		z_offset *= 3;
	}
	transform *= linalg.matrix4_translate_f32({0, 0, z_offset})
	return transform;
}

Tile_Hit_Info :: struct {
	tile_hit_count: [TILE_COUNT][TILE_COUNT]u8,
	total_hit_count: int,
	total_test_count: int,
}

foot_can_stand_at_position :: proc(game: ^Game, foot: Foot, position: Vec3, hit_info: ^Tile_Hit_Info = nil) -> bool {


	transform := foot_transform(foot);
	min_point_spacing := f32(0.5);
	scaled_bounds := foot.polygon_bounds;
	scaled_bounds.min *= foot_scale(foot);
	scaled_bounds.size *= foot_scale(foot);


	x_count := math.ceil(scaled_bounds.size.x / min_point_spacing) + 1;
	y_count := math.ceil(scaled_bounds.size.y / min_point_spacing) + 1;
	
	if hit_info != nil {
		hit_info^ = {total_test_count = int(x_count*y_count)};
	}

	space := foot.polygon_bounds.size / {f32(x_count), f32(y_count)};

	point_count_on_floor := 0;
	for xx in 0..<x_count {
	for yy in 0..<y_count {
		local_point := foot.polygon_bounds.min + {f32(xx)*space.x, f32(yy)*space.y};
		world_point := transform_point(v3_v2(local_point, 0), transform);

		tx, ty := get_tile_at_position(world_point);
		if tile_can_be_stood_on(game, tx, ty) {
			if hit_info != nil {
				hit_info.tile_hit_count[tx][ty] += 1;
				hit_info.total_hit_count += 1;
			}
			point_count_on_floor += 1;
			//debug_cube_centered(world_point, 0.3, {0, 1, 0, 1});
		}
		else {
			//debug_cube_centered(world_point, 0.3, {1, 0, 0, 1});
		}
	}}

	if point_count_on_floor < int(x_count*y_count/4) {
		return false;
	}
	return true;
}

transformed_rect_bounds :: proc(rect: Rect, transform: Matrix4) -> Rect {
	min := rect.min;
	max := rect.min + rect.size;
	
	c: [4]Vec2;
	c[0] = transform_point(Vec3{min.x, min.y, 0}, transform).xy;
    c[1] = transform_point(Vec3{min.x, max.y, 0}, transform).xy;
    c[2] = transform_point(Vec3{max.x, max.y, 0}, transform).xy;
    c[3] = transform_point(Vec3{max.x, min.y, 0}, transform).xy;

    return calculate_polygon_bounds(c[:]);
}

get_tile_at_position2 :: proc(position: Vec2) -> (tx, ty: int) {
	tx = int(math.floor(position.x / TILE_SIZE));
	ty = int(math.floor(position.y / TILE_SIZE));
	return;
}

get_tile_at_position :: proc(position: Vec3) -> (tx, ty: int) {
	tx = int(math.floor(position.x / TILE_SIZE));
	ty = int(math.floor(position.y / TILE_SIZE));
	return;
}

tile_is_in_bounds :: proc(tx, ty: int) -> bool {
	return tx >= 0 && ty >= 0 && tx < TILE_COUNT && ty < TILE_COUNT;
}

tile_can_be_stood_on :: proc(game: ^Game, tx, ty: int) -> bool {
	return tile_is_in_bounds(tx, ty) && game.tiles[tx][ty].dead_time < TILE_TIME_UNTIL_FULLY_DEAD;
}

point_can_be_stood_on :: proc(game: ^Game, point: Vec2) -> bool {
	tx, ty := get_tile_at_position2(point);
	return tile_can_be_stood_on(game, tx, ty);
}

add_insect_blood :: proc(position: Vec3) {
	ps := &blood_particle_system;

	n := 3 + rand.int31_max(4);
	for ii in 0..<n {
		add_particle(ps, {
			color = {0, 1, 0, 1},
			p = position,
			size = rand.float32_range(0.2, 1.0),
			dir = {rand.float32()*2-1, rand.float32()*2-1, 0},
			speed = rand.float32()*25,
			time_remaining = 2.0 + rand.float32()*2.1,
		});
	}
}
add_foot_blood :: proc(position: Vec3) {
	ps := &blood_particle_system;

	n := 1 + rand.int31_max(1);
	for ii in 0..<n {
		add_particle(ps, {
			color = {1, 0, 0, 1},
			p = position,
			size = rand.float32_range(0.1, 0.4),
			dir = {rand.float32()*2-1, rand.float32()*2-1, 0},
			speed = rand.float32()*10,
			time_remaining = 2.0 + rand.float32()*2.1,
		});
	}
}

explode_foot :: proc(foot: ^Foot) {
	if foot.dead do return;

	foot.dead = true;
	foot.exploded = true;

	ps := &blood_particle_system;

	scale := foot_scale(foot^);
	n := int((1000 + rand.float32()*500)*(scale+1));

	radius_h := f32(2)*scale;

	for ii in 0..<n {
		add_particle(ps, {
			color = {1, 0, 0, 1},
			p = foot.position + {rand.float32_range(-radius_h, radius_h), rand.float32_range(-radius_h, radius_h), 0.05},
			size = rand.float32_range(0.4, 0.7) * (scale+1),
			dir = {rand.float32()*2-1, rand.float32()*2-1, 0},
			speed = rand.float32()*20*(1+scale),
			time_remaining = 2.0 + rand.float32()*2.1,
		});
	}
}

remove_creature :: proc(game: ^Game, id: Creature_Id) {
	game.creature_exists[id] = false;
	game.free_creatures[game.free_creature_count] = id;
	game.free_creature_count += 1;
}

foot_stomp :: proc(game: ^Game, foot: ^Foot) {
	play_sound(fmt.tprintf("sounds/stomp%d.mp3", rand.int31_max(3)));
	foot.time_since_last_stomp = 0;
	foot_transform := foot_transform(foot^);
	if foot.bigger_stomp_remaining_time > 0 {
		foot_transform *= linalg.matrix4_scale_f32({5, 1.5, 1});
		play_sound("sounds/Explosion9.wav");
	}
	inv_foot_transform := linalg.inverse(foot_transform);

	world_bounds := transformed_rect_bounds(foot.polygon_bounds, foot_transform);
	world_bounds_max := world_bounds.min + world_bounds.size;
	min_cx, min_cy := clamped_creature_chunk_at_position(game, world_bounds.min);
	max_cx, max_cy := clamped_creature_chunk_at_position(game, world_bounds_max);

	/*tx, ty := get_tile_at_position(foot.position);
	if tile_is_in_bounds(tx, ty) {
		game.tiles[tx][ty].hp -= 10;		
	}*/

	kill_count := 0;
	for cx in min_cx..=max_cx {
	for cy in min_cy..=max_cy {
		for c in game.creature_chunks[cx][cy].creatures {
			if !rect_contains(world_bounds, c.position.xy) {
				continue;
			}

			local_p := transform_point2d(c.position, inv_foot_transform);
			if rect_contains(foot.polygon_bounds, local_p.xy) && polygon_contains(foot.polygon, local_p.xy) {
				//fmt.printf("Splash! %d\n", c.id);
				add_insect_blood(v3_v2(c.position, 0.1));
				remove_creature(game, c.id);
				kill_count += 1;
			}
		}
	}}
	foot.kills += kill_count;
	foot.hp += kill_count;
	game.combo += f32(kill_count);
	update_foot_size(foot);
	game.score += kill_count * get_score_multiplier(game);
	if kill_count > 0 {
		if kill_count < 5 {
			play_sound("sounds/small_sauce1.mp3");
		}
		else if kill_count < 15 {
			play_sound("sounds/medium_sauce1.mp3");
		}
		else /*if kill_count < 5*/ {
			play_sound("sounds/big_sauce1.mp3");
		}
	}
}

update_foot_size :: proc(foot: ^Foot) {
	foot.size = 0.2 + math.logb_f32(f32(foot.kills+1))*0.01 + f32(foot.kills)*0.001;
}

spawn_creature :: proc(game: ^Game, add: Creature) -> bool {
	id : Creature_Id;
	if game.free_creature_count > 0 {
		id = game.free_creatures[game.free_creature_count];
		game.free_creature_count -= 1;
	}
	else if game.creature_count < MAX_CREATURES {
		id = game.creature_count;
		game.creature_count += 1;		
	}
	else {
		return false;
	}

	game.creature_exists[id] = true;
	game.creatures[id] = add;
	game.creatures[id].id = id;
	return true;
}

spawn_new_creatures :: proc(game: ^Game) {
	game.creature_spawn_cooldown -= dt * 0.01;
	/*spawn_radius := f32(ACTIVE_AREA_SIZE*0.5);
	area_center := game.area_min + ACTIVE_AREA_SIZE*0.5;
	for ii in 0..<20 {
		c := Creature{
			position = area_center + {rand.float32_range(-spawn_radius, spawn_radius), rand.float32_range(-spawn_radius, spawn_radius)},
		};
		if !spawn_creature(game, c) {
			break;
		}
	}*/

	neighbor_offsets := [4][2]int{
		{-1, 0},
		{+1, 0},
		{0, -1},
		{0, +1},
	};

	for tx in 0..<TILE_COUNT {
	for ty in 0..<TILE_COUNT {
		if game.tiles[tx][ty].dead_time > 0 do continue;

		game.tiles[tx][ty].spawn_cooldown -= dt;
		if game.tiles[tx][ty].spawn_cooldown > 0 do continue;


		for offset in neighbor_offsets {
			tc := Vec2{(f32(tx) + 0.5), (f32(ty) + 0.5)}*TILE_SIZE;

			if !tile_can_be_stood_on(game, tx+offset.x, ty+offset.y) {
				dir := Vec2{f32(offset.x), f32(offset.y)}*TILE_SIZE*0.48;
				side := vec2_rotate_cw(dir);
				spawn_creature(game, {
					position = tc + dir + side * (rand.float32()*2-1),
					z_rotation = vector_to_z_rotation(-dir),
				});
				game.tiles[tx][ty].spawn_cooldown = game.creature_spawn_cooldown;
			}
		}
	}}
}

closest_point_on_foot :: proc(foot: Foot, to_p: Vec2, max_range: f32) -> (result: Vec2, found: bool) {
	transform := foot_transform(foot);

	closest_d2 := max_range;
	closest_point: Vec2;
	for local_point in foot.polygon {
		point := transform_point2d(local_point, transform).xy;
		d2 := linalg.dot(point.xy - to_p, point.xy - to_p);
		if d2 < closest_d2 {
			closest_d2 = d2;
			closest_point = point;
		}
	}
	return closest_point, closest_d2 < max_range;
}

tick_creatures :: proc(game: ^Game) {
	map_bounds := Rect{min = 0, size = MAP_SIZE};
	for cx in 0..<CREATURE_CHUNK_COUNT {
	for cy in 0..<CREATURE_CHUNK_COUNT {
		min_cx := math.max(0, cx - 1);
		min_cy := math.max(0, cy - 1);
		max_cx := math.min(CREATURE_CHUNK_COUNT-1, cx + 1);
		max_cy := math.min(CREATURE_CHUNK_COUNT-1, cy + 1);

		for &c in game.creature_chunks[cx][cy].creatures {
			velocity := Vec2{math.cos(c.z_rotation), math.sin(c.z_rotation)}*2;

			c.bite_cooldown -= dt;
			//total_avoidance: Vec2;

			COHERENCE_RADIUS :: 5.0;
			ALIGNMENT_RADIUS :: 3.0;
			attack_vector: Vec2;
			coherence_vector: Vec2;
			n_coherence: f32;
			avoidance: Vec2;
			//alignment: f32 = c.z_rotation;
			alignment: Vec2 = {rand.float32(), rand.float32()}*3;
			n_alignment: f32 = 3;

			max_attack_range := f32(3);
			max_seek_attack_range := f32(20);
			max_bite_range := f32(1.5);
			is_attacking := false;
			attack_position: Vec2;
			for &giant in game.giants {
				for &foot, foot_index in giant.feet {
					if foot.dead || foot_index == giant.grabbed_foot do continue;
					foot_point, found_point := closest_point_on_foot(foot, c.position, max_attack_range);
					if !found_point do continue;
					diff := foot_point - c.position;
					distance := linalg.length(diff);
					if foot.time_since_last_stomp > 0.5 {
						if distance < max_attack_range {
							if c.bite_cooldown <= 0 && distance < max_bite_range {
								foot.hp -= 1;
								if foot.hp <= 0 {
									explode_foot(&foot)									
								}
								c.bite_cooldown = 10;
								add_foot_blood(v3_v2(foot_point, 0.1));
							}
							attack_position = foot_point;
							is_attacking = true;
							velocity = (diff / distance) * 1.5;
						}
						else if distance < max_seek_attack_range {
							coherence_vector += foot.position.xy*3;// * (COHERENCE_RADIUS-distance);
							n_coherence += 3;
						}
					}
					else {
						if distance < foot.size {
							avoidance += diff / distance * 3;
						}
					}
				}
			}

			for kx in min_cx..=max_cx {
			for ky in min_cy..=max_cy {
				for o in game.creature_chunks[kx][ky].creatures {
					if o.id == c.id do continue;

					diff := o.position - c.position;
					distance := linalg.length(diff);
					dir := diff / distance;
					if distance < COHERENCE_RADIUS {
						coherence_vector += o.position;// * (COHERENCE_RADIUS-distance);
						n_coherence += 1;
					}
					if distance < ALIGNMENT_RADIUS {
						alignment += Vec2{math.cos(o.z_rotation), math.sin(o.z_rotation)}// * (ALIGNMENT_RADIUS-distance);;
						n_alignment += 1;
						//alignment += o.z_rotation * (ALIGNMENT_RADIUS-distance);
					}
					AVOID_RADIUS :: 0.5;
					if distance < AVOID_RADIUS {
						avoidance += dir// * (AVOID_RADIUS-distance);
					}
				}
			}}


			velocity -= avoidance*0.3;
			if !is_attacking {
				if n_coherence > 0 {
					center := coherence_vector / n_coherence;
					velocity += (center - c.position)*0.01;
				}
				if n_alignment > 0 {
					alignment = alignment / n_alignment;

					velocity += (alignment-velocity)*0.01;
				}
			}

			//velocity -= velocity * (linalg.length(velocity) * dt * 2);



			c.position += velocity * dt;
			c.z_rotation = math.atan2(velocity.y, velocity.x);
			//c.z_rotation = math.angle_lerp(c.z_rotation, alignment, dt);

			if !point_can_be_stood_on(game, c.position) {
				remove_creature(game, c.id);
			}
			else {
				game.creatures[c.id].position = c.position;
				game.creatures[c.id].z_rotation = c.z_rotation;
				game.creatures[c.id].bite_cooldown = c.bite_cooldown;
			}


		}
	}}
}

Giant :: struct {
	size: f32,
	feet: [FOOT_COUNT]Foot,
	hip_center: Vec3,
	hip_z_rotation: f32,

	grabbed_foot: int,
	grab_foot_start_ground_p: Vec3,
	grabbed_foot_start_p: Vec3,

	repair_mode_remaining_time: f32,
}


Creature_Id :: u32;
Creature :: struct {
	id: Creature_Id,
	position: Vec2,
	z_rotation: f32,
	bite_cooldown: f32,
}
MAX_CREATURES :: 1000;

CREATURE_CHUNK_COUNT     :: 16;
CREATURE_CHUNK_SIZE_LOG2 :: 2;
CREATURE_CHUNK_SIZE      :: 1 << CREATURE_CHUNK_SIZE_LOG2;
ACTIVE_AREA_SIZE         :: CREATURE_CHUNK_COUNT * CREATURE_CHUNK_SIZE;

Creature_Chunk :: struct {
	creatures: [dynamic]Creature,
}

Power_Up_Type :: enum {
	HEAL,
	REPAIR_MODE,
	BIGGER_STOMP,
}
Power_Up :: struct {
	type: Power_Up_Type,
	time_remaining: f32,
	position: Vec3,
}
POWER_UP_RADIUS :: 2;
MAX_POWER_UP_COUNT :: 8;

TILE_COUNT :: 7;
TILE_SIZE :: 8;
MAP_SIZE :: TILE_COUNT * TILE_SIZE;
#assert(MAP_SIZE < ACTIVE_AREA_SIZE, "Active are must be bigger than map");
TILE_MAX_HP :: 200;

TILE_TIME_UNTIL_FULLY_DEAD :: 1.0;
Tile :: struct {
	hp: int,
	dead_time: f32,
	spawn_cooldown: f32,
}

tile_part_fall_speed : [len(cracked_floor_parts)]f32;

MAX_FOOT_DISTANCE_FROM_HIP_BASE :: 7;
FOOT_MIN_DISTANCE :: 2.5;
GAME_OVER_FADE_IN_DURATION :: 0.5;
GAME_OVER_DURATION_BEFORE_RESTARTABLE :: 2.0;

/*Creature_Draw_Instance :: struct {
	x, y, r, t: f32,
}*/
Creature_Draw_Instance :: [4]f32;

creature_instance_data: [10000]Creature_Draw_Instance;
creature_instance_buffer: GL_Buffer;

Game :: struct {
	started: bool,
	game_over: bool,
	game_over_duration: f32,
	score, display_score: int,
	combo: f32,
	score_multiplier: int,

	x_rotation: f32,
	z_rotation: f32,
	target_z_rotation: f32,
	camera_focus: Vec3,
	target_camera_focus: Vec3,
	camera_position: Vec3,
	camera_distance: f32,
	free_camera: bool,

	giants: [1]Giant,
	player_giant: ^Giant,
	area_min: Vec2,

	creature_exists: [MAX_CREATURES]bool,
	creatures: [MAX_CREATURES]Creature,
	free_creatures: [MAX_CREATURES]Creature_Id,
	free_creature_count: int,
	creature_count: u32,

	creature_chunk_arena: mem.Arena,

	creature_chunks: [CREATURE_CHUNK_COUNT][CREATURE_CHUNK_COUNT]Creature_Chunk,

	tiles: [TILE_COUNT][TILE_COUNT]Tile,

	creature_spawn_cooldown: f32,

	next_power_up_cooldown: f32,
	power_ups: [MAX_POWER_UP_COUNT]Power_Up,	
}

creature_chunk_at_position :: proc(game: ^Game, p: Vec2) -> (cx, cy: i32) {
	cx = i32(p.x - game.area_min.x) >> CREATURE_CHUNK_SIZE_LOG2;
	cy = i32(p.y - game.area_min.y) >> CREATURE_CHUNK_SIZE_LOG2;
	return;
}

clamped_creature_chunk_at_position :: proc(game: ^Game, p: Vec2) -> (cx, cy: u32) {
	icx, icy := creature_chunk_at_position(game, p);

	return u32(math.clamp(icx, 0, CREATURE_CHUNK_COUNT-1)), u32(math.clamp(icy, 0, CREATURE_CHUNK_COUNT-1))
}

checked_creature_chunk_at_position :: proc(game: ^Game, p: Vec2) -> (cx, cy: u32, ok: bool) {
	icx, icy := creature_chunk_at_position(game, p);
	in_bounds := (icx >= 0 && icx < CREATURE_CHUNK_COUNT && icy >= 0 && icy < CREATURE_CHUNK_COUNT);
	return u32(icx), u32(icy), in_bounds;
}

update_creature_chunks :: proc(game: ^Game) {
	mem.arena_free_all(&game.creature_chunk_arena);
	allocator := mem.arena_allocator(&game.creature_chunk_arena);

	for cy in 0..<CREATURE_CHUNK_COUNT {
	for cx in 0..<CREATURE_CHUNK_COUNT {
		game.creature_chunks[cx][cy].creatures = make([dynamic]Creature, 0, 500, allocator);
	}}

	for id in 0..<game.creature_count {
		if !game.creature_exists[id] do continue;

		c := &game.creatures[id];
		cx, cy, ok := checked_creature_chunk_at_position(game, c.position);

		if ok {
			append(&game.creature_chunks[cx][cy].creatures, c^);
		}
		else {
			remove_creature(game, id);
		}
	}
}

calculate_hip_target_center :: proc(giant: Giant) -> Vec3 {
	result := Vec3{0, 0, 0};
	for foot in giant.feet {
		result.xy += foot.position.xy;
	}
	return result / len(giant.feet);
}

calculate_hip_target_z_rotation :: proc(giant: Giant) -> f32 {
	assert(len(giant.feet) == 2);

	feet_diff := giant.feet[LEFT].position - giant.feet[RIGHT].position;
	forward := Vec2{feet_diff.y, -feet_diff.x};
	return math.atan2(forward.y, forward.x);
}

calculate_polygon_bounds :: proc(polygon: []Vec2) -> Rect {
	min := polygon[0];
	max := polygon[0];

	for ii in 1..<len(polygon) {
		p := polygon[ii];
		min.x = math.min(p.x, min.x);
		min.y = math.min(p.y, min.y);
		max.x = math.max(p.x, max.x);
		max.y = math.max(p.y, max.y);
	}

	return {min = min, size = max-min};
}

polygon_contains :: proc(polygon: []Vec2, p: Vec2) -> bool {
	ii := len(polygon)-1;
	for jj := 0; jj < len(polygon); {
		v := polygon[jj] - polygon[ii];
		n := Vec2{v.y, -v.x};
		if linalg.dot(n, p) > linalg.dot(n, polygon[ii]) {
			// Point is above the line
			return false;
		}
		ii = jj;
		jj += 1;
	}
	return true;
}

create_foot_collision_polygon :: proc(mesh: ^Mesh) -> []Vec2 {
	points := make([dynamic]Vec2, 0, 32);

	min := mesh.positions[0].xy;
	max := mesh.positions[0].xy;
	for vi in 0..<mesh.vertex_count {
		p := mesh.positions[vi];
		if p.x < min.x || (p.x == min.x && p.y < min.y) {
			min = p.xy;
		}

		if p.x > max.x || (p.x == max.x && p.y > max.y) {
			max = p.xy;
		}
	}
	v := max - min;
	n := Vec2{v.y, -v.x};

	above, below: Vec2;
	above_d, below_d: f32;
	for vi in 0..<mesh.vertex_count {
		p := mesh.positions[vi];

		d := linalg.dot(n, p.xy) - linalg.dot(n, min);
		if d > above_d {
			above = p.xy;
			above_d = d;
		}
		else if d < below_d {
			below = p.xy;
			below_d = d;
		}
	}
	append(&points, min);
	append(&points, above);
	append(&points, max);
	append(&points, below);

	for pi := 0; pi < len(points); pi += 1 {
		pj := (pi+1)%len(points);

		v := points[pj] - points[pi];
		n := Vec2{v.y, -v.x};

		above: Vec2;
		above_d: f32;
		for vi in 0..<mesh.vertex_count {
			p := mesh.positions[vi];

			d := linalg.dot(n, p.xy) - linalg.dot(n, points[pi]);
			if d > above_d {
				above = p.xy;
				above_d = d;
			}
		}
		if above_d > 0.1 {
			inject_at(&points, pj, above);
			pi -= 1;
		}
	}
	return points[:];
}

game_restart :: proc(game: ^Game) {
	game_init(game);
}

game_init :: proc(game: ^Game) {
	game^ = {
		creature_spawn_cooldown = 1.0,
		free_camera = false,
	}


	for tx in 0..<TILE_COUNT {
	for ty in 0..<TILE_COUNT {
		game.tiles[tx][ty] = {
			TILE_MAX_HP,
			0,
			0,
		};
	}}

	map_center := Vec3{MAP_SIZE, MAP_SIZE, 0} * 0.5;
	game.giants[0].feet[LEFT] = {
		mesh = &foot_left_mesh,
		position = map_center,
		//z_rotation = math.TAU*-0.15,
	}
	game.giants[0].feet[RIGHT] = {
		mesh = &foot_right_mesh,
		position = map_center,
		//z_rotation = math.TAU*0.1,
	}
	for &giant in game.giants {
		giant.grabbed_foot = -1;
		for &foot in giant.feet {
			foot.hp = 100;
			update_foot_size(&foot);
			foot.z_rotation = giant.hip_z_rotation;
			foot.polygon = create_foot_collision_polygon(foot.mesh);
			foot.polygon_bounds = calculate_polygon_bounds(foot.polygon);
		}
		giant.feet[0].position.y += giant.feet[0].size * MAX_FOOT_DISTANCE_FROM_HIP_BASE * 1.0;

		giant.hip_center = calculate_hip_target_center(giant);
		giant.hip_z_rotation = calculate_hip_target_z_rotation(giant);
	}
	game.player_giant = &game.giants[0];

	/*spawn_radius := f32(20);
	for ii in 0..<1000 {
		/*game.creature_exists[ii] = true;
		creature := &game.creatures[game.creature_count];
		game.creature_count += 1;*/

		spawn_creature(game, {
			id = u32(ii),
			position = map_center.xy + Vec2{
				rand.float32_range(-spawn_radius, spawn_radius),
				rand.float32_range(-spawn_radius, spawn_radius)
			},
			z_rotation = rand.float32_range(0, math.TAU),
		});
	}*/

	/*add_power_up(game, {
		position = map_center + {5, 4, 0}, 
		type = .BIGGER_STOMP, 
		time_remaining = 5.0
	});

	add_power_up(game, {
		position = map_center + {5, 0, 0}, 
		type = .REPAIR_MODE, 
		time_remaining = 5.0
	});*/

	mem.arena_init(&game.creature_chunk_arena, make([]u8, mem.Megabyte*32));
	update_creature_chunks(game);

	game.z_rotation = game.player_giant.hip_z_rotation;
	game.target_z_rotation = game.z_rotation;
	game.x_rotation  = 0.15 * math.PI;
	game.camera_distance = 20;
	game.camera_focus = game.player_giant.hip_center;
	game.target_camera_focus = game.camera_focus;
	
}

add_power_up :: proc(game: ^Game, add: Power_Up) {
	index := -1;
	for existing, ii in game.power_ups {
		if existing.time_remaining <= 0 {
			index = ii;
		}
	}
	if index != -1 {
		game.power_ups[index] = add;
	}
}

Projection :: struct {
	fov_y, aspect, near, far: f32
}
get_camera_direction :: proc(transform: Matrix4, proj: Projection, position: Vec2) -> Vec3 {
	tan_half_fov := math.tan(proj.fov_y * 0.5);
	forward := transform[2].xyz;
	up := transform[1].xyz;
	right := transform[0].xyz;


	result := Vec3{
		proj.aspect * tan_half_fov * (position.x*2.0 - 1.0),
		tan_half_fov * ((1.0-position.y)*2.0 - 1.0),
		-1,
	};

	result = transform_vector(result, transform);
	return linalg.normalize(result);
}

tick_player_giant :: proc(game: ^Game, giant: ^Giant, mouse_ray: Ray) {
	mouse_ground_p: Vec3;
	mouse_ground_t, mouse_hit_ground := ray_hit_plane(mouse_ray, {0, 0, 0}, {0, 0, 1});
	if mouse_hit_ground {
		mouse_ground_p = ray_get_position(mouse_ray, mouse_ground_t);
		//debug_cube_centered(mouse_ground_p, 1, {1, 0, 1, 1});
	}


	if giant.grabbed_foot != -1 {
		if game.game_over {
			giant.grabbed_foot = -1;
		}
		else if !left_mouse_is_down {
			@static hit_info: Tile_Hit_Info;
			foot := &giant.feet[giant.grabbed_foot];
			if foot_can_stand_at_position(game, foot^, foot.position, &hit_info) {

				total_damage := 100 * foot_scale(foot^);
				one_point_factor := 1 / f32(hit_info.total_hit_count)/* / f32(hit_info.total_test_count)*/
				one_point_damage := one_point_factor * total_damage;
				//fmt.printf("total damage: %f, one damage: %f\n", total_damage, one_point_damage);
				for tx in 0..<TILE_COUNT {
				for ty in 0..<TILE_COUNT {
					if hit_info.tile_hit_count[tx][ty] > 0 {
						if giant.repair_mode_remaining_time > 0 {
							game.tiles[tx][ty].hp = TILE_MAX_HP;
							game.tiles[tx][ty].dead_time = 0;
						}
						else {
							damage := int(math.ceil(f32(hit_info.tile_hit_count[tx][ty]) * one_point_damage));
							game.tiles[tx][ty].hp -= damage;
						}

					}
				}}

				foot_stomp(game, foot)
				giant.grabbed_foot = -1;
			}
		}
	}

	if giant.grabbed_foot != -1 {
		foot_index := giant.grabbed_foot;
		foot := &giant.feet[foot_index];
		foot.grabbed_t = math.min(foot.grabbed_t+dt*5, 1.0);
		offset_from_start := (mouse_ground_p - giant.grab_foot_start_ground_p);
		new_p := giant.grabbed_foot_start_p + offset_from_start;

		hip_forward := z_rotation_to_vector(giant.hip_z_rotation);
		other_foot := giant.feet[foot_index ~ 0x1];
		other_foot_forward := z_rotation_to_vector(other_foot.z_rotation);
		center_barrier_vector := vec2_rotate(other_foot_forward.xy, cw = foot_index == RIGHT);
		center_barrier_sd := linalg.dot(center_barrier_vector, new_p.xy) - linalg.dot(center_barrier_vector, other_foot.position.xy) + FOOT_MIN_DISTANCE*foot_scale(foot^);
		if center_barrier_sd > 0 {

			new_p.xy -= center_barrier_vector * center_barrier_sd;
			offset_from_start = new_p - giant.grab_foot_start_ground_p;
		}

		max_foot_distance_from_hip := giant.size * MAX_FOOT_DISTANCE_FROM_HIP_BASE;
		hip_diff := new_p - giant.hip_center;
		distance_from_hip := linalg.length(hip_diff);
		from_hip_dir := distance_from_hip > 0.01 ? hip_diff / distance_from_hip : other_foot_forward;
		if distance_from_hip > max_foot_distance_from_hip {
			new_p = giant.hip_center + from_hip_dir * max_foot_distance_from_hip;
		}
		foot.position = new_p;
		
		foot_forward := other_foot_forward;
		//from_hip_rotation := vector_to_z_rotation(from_hip_dir.xy);
		from_hip_rotation := math.angle_lerp(
			foot.z_rotation, 
			vector_to_z_rotation(offset_from_start.xy), math.min(1, linalg.length(offset_from_start)/max_foot_distance_from_hip));

		t := math.angle_diff(other_foot.z_rotation, from_hip_rotation) / (math.PI*0.5);
		t0 := t;

		if foot_index == RIGHT {
			t = -t; // 0 - 1
		}
		else {
		}
		t -= 0.5; // -0.5 - 0.5
		t = math.abs(t); // 0.5 - 0.5 
		t *= 2;
		//debug_text = fmt.tprintf("T0: %f - > T1 %f", t0, t);
		foot.z_rotation = math.angle_lerp(from_hip_rotation, other_foot.z_rotation, math.min(1, t));

		//giant.hip_z_rotation = math.angle_lerp(other_foot.z_rotation, foot.z_rotation, 0.5);
		{
			ad := math.angle_diff(other_foot.z_rotation, foot.z_rotation);
			if math.abs(ad) > math.PI {
				ad = 0;
			}
			giant.hip_z_rotation = other_foot.z_rotation + ad * 0.5;
			//debug_text = fmt.tprintf("hip rotation: %f, ad: %f, other: %f", giant.hip_z_rotation, ad, other_foot.z_rotation);
		}
		//giant.hip_z_rotation = (other_foot.z_rotation + foot.z_rotation) * 0.5;

		target_hip_center := calculate_hip_target_center(giant^);
		//giant.hip_center = linalg.lerp(giant.hip_center, target_hip_center, dt*4);
		giant.hip_center = target_hip_center;

		/*angle_diff := math.angle_diff(other_foot.z_rotation, from_hip_rotation);
		if angle_diff < 0 {
			debug_text = fmt.tprintf("Angle diff: %f", angle_diff);
			foot.z_rotation = from_hip_rotation;
			if angle_diff < -math.PI*0.25 && angle_diff > -math.PI*0.5 {
				t := -angle_diff; // 0.25 - 0.5
				t -= 0.25; // 0 - 0.25
				t *= 4;    // 0 - 1
				//foot.z_rotation = math.angle_lerp(foot.z_rotation+math.TAU, other_foot.z_rotation, t);
				//foot.z_rotation -= angle_diff * t;
			}
			else {
				foot.z_rotation = other_foot.z_rotation;
			}
		}*/
		//foot.z_rotation = from_hip_rotation;
		/*dot := linalg.dot(other_foot_forward, from_hip_dir);
		dot0 := dot;
		if dot > 0.7 {
			dot = (dot - 0.7) / 0.3;
			//foot.z_rotation -= (1.0 - dot)*math.PI;
		}
		else if dot > 0.0 {
			dot = dot / 0.5;
		}
		foot.z_rotation = other_foot.z_rotation - math.PI*dot*0.5;
		
		debug_text = fmt.tprintf("Dott %f, dot0 %f", dot, dot0);*/

		//foot.z_rotation = giant.hip_z_rotation;

		for &pu in game.power_ups {
			if pu.time_remaining <= 0 do continue;
			if linalg.distance(pu.position.xy, foot.position.xy) < POWER_UP_RADIUS {
				take_power_up(giant, foot, &pu);
			}
		}
	}
	else if !game.game_over {
		for foot, foot_index in giant.feet {
			hovered := false;
			transform := foot_transform_3d(foot, foot_index == giant.grabbed_foot);
			mesh := foot.mesh;
			for tri := 0; tri < int(mesh.index_count)-2; tri += 3 {
				hit_t, did_hit := ray_hit_triangle(mouse_ray, 
					transform_point(mesh.positions[mesh.indices[tri+0]], transform),
					transform_point(mesh.positions[mesh.indices[tri+1]], transform),
					transform_point(mesh.positions[mesh.indices[tri+2]], transform)) 
				if did_hit {
					hovered = true;
				}
			}

			if hovered && left_mouse_got_pressed {
				giant.grabbed_foot = foot_index;
				giant.grabbed_foot_start_p = foot.position;
				giant.grab_foot_start_ground_p = mouse_ground_p;
			}
		}
	}
}

debug_text: string;

take_power_up :: proc(giant: ^Giant, foot: ^Foot, pu: ^Power_Up) {
	pu.time_remaining = 0;

	switch pu.type {
		case .HEAL: {
			foot.hp += 50;
			play_sound("sounds/heal.wav");
		}
		case .REPAIR_MODE: {
			giant.repair_mode_remaining_time = 10;
			play_sound("sounds/repair_mode.wav");
		}
		case .BIGGER_STOMP: {
			foot.bigger_stomp_remaining_time = 10;
			play_sound("sounds/bigger_stomp_pickup.wav");
		}
	}
}

draw_power_ups :: proc(game: ^Game) {
	for pu in game.power_ups {
		if pu.time_remaining <= 0 do continue;

		shader := color_shader;
		set_shader(shader);
		u_transform := GL.GetUniformLocation(shader, "transform");
		u_scale_color := GL.GetUniformLocation(shader, "scale_color");

		translation := linalg.matrix4_translate_f32(pu.position + {0, 0, 2.4 + math.cos(get_time()*5)*0.7});
		//rotation := linalg.matrix4_look_at_f32(pu.position, game.camera_position, {0, 0, 1});
		rotation := linalg.matrix4_rotate_f32(get_time(), {0, 0, 1});
		transform := translation * rotation;
		GL.UniformMatrix4fv(u_transform, transform);
		GL.Uniform3f(u_scale_color, 1, 1, 1);
		mesh: ^Mesh;
		switch pu.type {
			case .HEAL: mesh = &heal_mesh;
			case .REPAIR_MODE: mesh = &wrench_mesh;
			case .BIGGER_STOMP: mesh = &bigger_stomp_mesh;
		}

		draw_mesh(mesh);
	}
}

tick_power_ups :: proc(game: ^Game) {
	for &pu in game.power_ups {
		pu.time_remaining -= dt;
	}
	game.next_power_up_cooldown -= dt;
	if game.next_power_up_cooldown <= 0 {
		spawn_radius := f32(ACTIVE_AREA_SIZE*0.5);
		spawn_radius = math.min(spawn_radius, MAP_SIZE*0.5);
		map_center := Vec3{MAP_SIZE, MAP_SIZE, 0} * 0.5;



		type: Power_Up_Type;
		if rand.float32() > 0.8 {
			type = .BIGGER_STOMP;
		}
		else if rand.float32() > 0.5 {
			type = .HEAL;
		}
		else {
			type = .REPAIR_MODE;
		}

		add_power_up(game, {
			position = map_center + {rand.float32_range(-spawn_radius, spawn_radius), rand.float32_range(-spawn_radius, spawn_radius), 0},
			type = type,
			time_remaining = 30.0,
		});

		game.next_power_up_cooldown = 5.0;
	}
}

game_tick_and_draw :: proc(game: ^Game) {
	if !game.started {
		if left_mouse_got_pressed {
			game.started = true;
		}
	}
	if game.game_over {
		game.game_over_duration += dt;
		if game.game_over_duration > GAME_OVER_DURATION_BEFORE_RESTARTABLE && left_mouse_got_pressed {
			game_restart(game);
		}
	}
	game.combo -= dt*1*game.combo*0.5;
	if game.combo < 0 {
		game.combo = 0;
	}
	update_score_multiplier(game);
	game.camera_focus = linalg.lerp(game.camera_focus, game.target_camera_focus, dt*4);
	camera_focus := game.camera_focus;

	//game.area_min = camera_focus.xy - ACTIVE_AREA_SIZE*0.5;
	game.area_min = Vec2(MAP_SIZE)*0.5 - ACTIVE_AREA_SIZE*0.5;
	if game.started {
		tick_power_ups(game);
		spawn_new_creatures(game);
		update_creature_chunks(game);
		tick_creatures(game);
	}

	if game.free_camera {
		if right_mouse_is_down {
			game.z_rotation -= mouse_delta.x / window_size.x * math.TAU;
			game.x_rotation -= mouse_delta.y / window_size.y * math.TAU; 		
		}
		game.camera_distance -= game.camera_distance * f32(mouse_scroll_amount)*0.001;
	}
	else {
		if game.player_giant.grabbed_foot == -1 {
			target_z_rotation := game.player_giant.hip_z_rotation - math.PI*0.5;
			diff := math.angle_diff(game.target_z_rotation, target_z_rotation);
			if math.abs(diff) > 0.2*math.TAU {
				game.target_z_rotation = target_z_rotation;
			}

			game.z_rotation = math.angle_lerp(game.z_rotation, game.target_z_rotation, dt*4);
			game.target_camera_focus = game.player_giant.hip_center;
		}
		game.x_rotation = 0.150*math.PI;
		game.camera_distance = game.player_giant.size*40;
	}

	GL.Viewport(0, 0, window_width, window_height);
	flip_z_axis := true;
	z_rotation := game.z_rotation;
	x_rotation := game.x_rotation;
	camera_transform := linalg.MATRIX4F32_IDENTITY;
	camera_transform *= linalg.matrix4_translate_f32(camera_focus);
	camera_transform *= linalg.matrix4_rotate_f32(z_rotation, {0, 0, 1});
	camera_transform *= linalg.matrix4_rotate_f32(x_rotation, {1, 0, 0});
	camera_transform *= linalg.matrix4_translate_f32({0, 0, game.camera_distance});
	game.camera_position = camera_transform[3].xyz;

	camera_view := linalg.inverse(camera_transform);

	camera_proj_settings := Projection {
		fov_y = math.to_radians(f32(60)),
		aspect = window_size.x / window_size.y,
		near = f32(0.01),
		far = f32(1000),
	}
	camera_proj := linalg.matrix4_perspective_f32(
		camera_proj_settings.fov_y,
	 	camera_proj_settings.aspect, 
	 	camera_proj_settings.near, 
	 	camera_proj_settings.far, 
	 	flip_z_axis);

	ray := Ray{origin = camera_transform[3].xyz, direction = get_camera_direction(camera_transform, camera_proj_settings, mouse_p / window_size)};

	if game.started {
		tick_player_giant(game, game.player_giant, ray);
	}
	
	for &giant in game.giants {
		giant.repair_mode_remaining_time -= dt;
		#assert(FOOT_COUNT == 2);
		giant.size = math.min(giant.feet[0].size, giant.feet[1].size);
		for &foot, foot_index in giant.feet {
			foot.bigger_stomp_remaining_time -= dt;
			if foot.dead {
				game.game_over = true;
			}
			if game.game_over {
				foot.dead = true;
			}
			if game.game_over {
				foot.position.z = -square(game.game_over_duration*4);
			}
			else if giant.grabbed_foot != foot_index {

				if !foot_can_stand_at_position(game, foot, foot.position) {
					//debug_text = "Would die!";
					game.game_over = true;
					//foot.dead = true;
				}

				/*tx, ty := get_tile_at_position(foot.position);
				if !tile_can_be_stood_on(game, tx, ty) {
					game.game_over = true;
				}*/
			}
		}
	}

	for tx in 0..<TILE_COUNT {
	for ty in 0..<TILE_COUNT {
		if game.tiles[tx][ty].hp <= 0 {
			game.tiles[tx][ty].dead_time += dt;
		}
	}}

	start_draw_3d(camera_view, camera_proj);

	draw_power_ups(game);
	{
		shader := textured_shader;
		set_shader(shader);

		u_transform := GL.GetUniformLocation(shader, "transform");
		u_scale_color := GL.GetUniformLocation(shader, "scale_color");
		u_use_scale_color := GL.GetUniformLocation(shader, "use_scale_color");
		u_use_light := GL.GetUniformLocation(shader, "use_light");

		for &giant in game.giants {
			/*if giant.grabbed_foot == -1 {
				target_hip_center := calculate_hip_target_center(giant);
				//giant.hip_center = linalg.lerp(giant.hip_center, target_hip_center, dt*4);
				giant.hip_center = target_hip_center;
				//target_hip_z_rotation := calculate_hip_target_z_rotation(game.giants[0]);
				//giant.hip_z_rotation = target_hip_z_rotation;
				//giant.hip_z_rotation = math.angle_lerp(giant.hip_z_rotation, target_hip_z_rotation, dt*4);
			}*/
			for &foot, foot_index in giant.feet {
				if foot.exploded do continue;
				is_grabbed := foot_index == giant.grabbed_foot;
				if !is_grabbed {
					foot.grabbed_t = math.max(0, foot.grabbed_t-dt*6);
				}
				foot.time_since_last_stomp += dt;
				transform := foot_transform_3d(foot, is_grabbed);
				
				
				GL.UniformMatrix4fv(u_transform, transform);
				GL.Uniform1i(u_use_scale_color, 1);
				GL.Uniform1i(u_use_light, 1);

				damaged := math.max(0, 1-f32(foot.hp)/100);
				color := Vec3{1, 1-damaged, 1-damaged};
				GL.Uniform3f(u_scale_color, color.x, color.y, color.z);
				set_texture(&foot_texture);
				draw_mesh(foot.mesh);


				when !true {
					debug_ground_z := f32(0.1);
					for ii in 0..<len(foot.polygon) {
						jj := (ii + 1) % len(foot.polygon);

						debug_line(
							transform_point(v3_v2(foot.polygon[ii], debug_ground_z), transform), 
							transform_point(v3_v2(foot.polygon[jj], debug_ground_z), transform), 
							{0, 1, 0, 1});
					}
					debug_horizontal_rect(foot.polygon_bounds, debug_ground_z, {1, 1, 1, 1}, transform);

					world_bounds := transformed_rect_bounds(foot.polygon_bounds, transform);
					debug_horizontal_rect(world_bounds, debug_ground_z, {0, 0, 1, 1}, linalg.MATRIX4F32_IDENTITY);
				}
			}
			when !true {
				debug_ray(giant.hip_center+{0, 0, 0.1}, z_rotation_to_vector(giant.hip_z_rotation), {1, 0, 0, 1});
				debug_cube_centered(giant.hip_center, giant.size, {1, 0, 0, 1});
			}

		}
	}

	when false
	{	
		shader := color_shader;
		set_shader(shader);
		u_transform := GL.GetUniformLocation(shader, "transform");
		for cx in 0..<CREATURE_CHUNK_COUNT {
		for cy in 0..<CREATURE_CHUNK_COUNT {
			chunk_rect := Rect{min = game.area_min + {f32(cx) * CREATURE_CHUNK_SIZE, f32(cy) * CREATURE_CHUNK_SIZE}, size = CREATURE_CHUNK_SIZE};
			debug_horizontal_rect(chunk_rect, 0.1, {0, 1, 0, 1}, linalg.MATRIX4F32_IDENTITY);

			for c in game.creature_chunks[cx][cy].creatures {
				transform := linalg.matrix4_translate_f32(v3_v2(c.position));
				transform *= linalg.matrix4_rotate_f32(c.z_rotation-math.PI*0.5, {0, 0, 1});
				
				GL.UniformMatrix4fv(u_transform, transform);
				draw_mesh(&creature1_mesh);
			}
		}}
	}
	else {
		// Instanced
		{
			shader := bug_shader;
			set_shader(shader);
			u_transform := GL.GetUniformLocation(shader, "transform");

			mesh := &creature1_mesh;
			//mesh := &foot_left_mesh;
			set_mesh(mesh);

			instance_count := 0;
			/*for ii in 0..<20 {
				creature_instance_data[instance_count] = {
					/*x = */f32(ii*2),
					/*y = */0,
					/*z = */0,
					/*w = */0,
				};
				instance_count += 1;
			}*/
			for cx in 0..<CREATURE_CHUNK_COUNT {
			for cy in 0..<CREATURE_CHUNK_COUNT {
				/*chunk_rect := Rect{min = game.area_min + {f32(cx) * CREATURE_CHUNK_SIZE, f32(cy) * CREATURE_CHUNK_SIZE}, size = CREATURE_CHUNK_SIZE};
				debug_horizontal_rect(chunk_rect, 0.1, {0, 1, 0, 1}, linalg.MATRIX4F32_IDENTITY);*/

				for c in game.creature_chunks[cx][cy].creatures {
					/*transform := linalg.matrix4_translate_f32(v3_v2(c.position));
					transform *= linalg.matrix4_rotate_f32(c.z_rotation-math.PI*0.5, {0, 0, 1});
					
					GL.UniformMatrix4fv(u_transform, transform);
					draw_mesh(&creature1_mesh);*/
					creature_instance_data[instance_count] = {
						c.position.x,
						c.position.y,
						c.z_rotation-math.PI*0.5,
						get_time(),
					};
					instance_count += 1;
				}
			}}

			GL.Uniform4fv(GL.GetUniformLocation(shader, "data"), creature_instance_data[:instance_count]);

			//GL.BindBuffer(GL.UNIFORM_BUFFER, creature_instance_buffer);
			//GL.BufferSubData(GL.UNIFORM_BUFFER, 0, size_of(Creature_Draw_Instance)*instance_count, &creature_instance_data[0]);
			//fmt.printf("IOJWADO\n");
			//GL.Uniform1i(GL.GetUniformLocation(shader, "instances"), 0);
			//transform := linalg.matrix4_translate_f32({get_time()*10, 0, 0});
			//GL.UniformMatrix4fv(u_transform, transform);
			GL.DrawElementsInstanced(GL.TRIANGLES, cast(int)mesh.index_count, OPENGL_VERTEX_INDEX_TYPE, 0, instance_count);
		}
	}

	when false
	{
		shader := textured_shader;
		set_shader(shader);


		u_transform := GL.GetUniformLocation(shader, "transform");

		floor_scale := Vec3(FLOOR_TILING_PER_QUAD*10);
		transform := linalg.matrix4_scale_f32(floor_scale);

		offset := camera_focus / floor_scale;
		offset.x = math.round(offset.x*FLOOR_TILING_PER_QUAD)/FLOOR_TILING_PER_QUAD;
		offset.y = math.round(offset.y*FLOOR_TILING_PER_QUAD)/FLOOR_TILING_PER_QUAD;
		transform *= linalg.matrix4_translate_f32(offset);

		GL.UniformMatrix4fv(u_transform, transform);

		set_texture(&floor_texture);

		draw_mesh(&floor_tile_mesh);
	}
	else {
		shader := textured_shader;
		set_shader(shader);


		u_transform := GL.GetUniformLocation(shader, "transform");
		GL.Uniform1i(GL.GetUniformLocation(shader, "use_scale_color"), 0);
		GL.Uniform1i(GL.GetUniformLocation(shader, "use_light"), 0);
		for tx in 0..<TILE_COUNT {
		for ty in 0..<TILE_COUNT {
			tile := game.tiles[tx][ty];
			
			
			if tile.dead_time == 0 {
				texture: ^Texture;
				if tile.hp <= TILE_MAX_HP/4 {
					texture = &floor_texture_cracked[1];
				}
				else if tile.hp < TILE_MAX_HP/2 {
					texture = &floor_texture_cracked[0];
				}
				else {
					texture = &floor_texture;
				}
				set_texture(texture);
				transform := linalg.matrix4_translate_f32({(f32(tx)+0.5) * TILE_SIZE, (f32(ty)+0.5) * TILE_SIZE, 0}) * linalg.matrix4_scale_f32(TILE_SIZE);
				GL.UniformMatrix4fv(u_transform, transform);

				draw_mesh(&floor_tile_mesh);
			}
			else {
				if tile.dead_time >= TILE_TIME_UNTIL_FULLY_DEAD*10 {
					continue;
				}
				set_texture(&floor_texture_cracked[1]);
				transform := linalg.matrix4_translate_f32({(f32(tx)+0.5) * TILE_SIZE, (f32(ty)+0.5) * TILE_SIZE, 0}) * linalg.matrix4_scale_f32(TILE_SIZE*0.5);
				transform *= linalg.matrix4_rotate_f32(math.PI, {0, 0, 1});
				GL.UniformMatrix4fv(u_transform, transform);
				draw_index := int(get_time()) % 13;
				for part_index in 0..<len(cracked_floor_parts) {
					//if draw_index != part_index do continue;
					z := math.min(0, 1.0 - square(tile.dead_time) * tile_part_fall_speed[part_index]);
					z += math.cos(tile.dead_time*tile_part_fall_speed[part_index]*5)*math.min(0.1, tile.dead_time);
					part_transform := transform * linalg.matrix4_translate_f32({0, 0, z})
					GL.UniformMatrix4fv(u_transform, part_transform);
					draw_mesh(&cracked_floor_parts[part_index]);
				}
			}


			/*mesh := &cracked_floor;
			set_mesh(mesh);


			
			prev_index_offset: u32 = 0;
			for sub_index in 0..<MAX_SUB_MESH_COUNT-1 {
				/*if it > 0 && index_offset == 0 {
					break;
				}*/
				next_offset := mesh.sub_mesh_index_offsets[sub_index]
				if next_offset <= prev_index_offset do break;

				count := next_offset - prev_index_offset;

				GL.UniformMatrix4fv(u_transform, transform);
				if sub_index == draw_index {
					draw_active_mesh_index_range(mesh, prev_index_offset, count);
				}
				
				prev_index_offset = next_offset;
			}*/
		}}
	}

	when !true {
		@static initialized_triangle := false;

		@static vertex_buffer: GL.Buffer;
		@static position_offset, color_offset: uintptr;
		if vertex_buffer == 0 {
			scale := f32(1.0);
			positions := [3]Vec3 {
				Vec3{-1, 0, -1} * scale,
				Vec3{+0, 0, +1} * scale,
				Vec3{+1, 0, -1} * scale,
			}

			colors := [3]Vec3 {
				{1, 0, 0},
				{0, 1, 0},
				{0, 0, 1},
			};

			vertex_buffer = GL.CreateBuffer();
			GL.BindBuffer(GL.ARRAY_BUFFER, vertex_buffer);
			GL.BufferData(GL.ARRAY_BUFFER, size_of(positions) + size_of(colors), nil, GL.STATIC_DRAW);

			offset : uintptr;
			GL.BufferSubData(GL.ARRAY_BUFFER, offset, size_of(positions), raw_data(positions[:]));
			position_offset = offset;
			offset += size_of(positions);

			GL.BufferSubData(GL.ARRAY_BUFFER, offset, size_of(colors), raw_data(colors[:]));
			color_offset = offset;
			offset += size_of(colors);
		}

		GL.UseProgram(GL.Program(color_program));
		GL.BindBuffer(GL.ARRAY_BUFFER, vertex_buffer);

		GL.EnableVertexAttribArray(0);
		GL.VertexAttribPointer(0, 3, GL.FLOAT, false, 0, position_offset);

		GL.EnableVertexAttribArray(1);
	    GL.VertexAttribPointer(1, 3, GL.FLOAT, false, 0, color_offset);
	    GL.DrawArrays(GL.TRIANGLES, 0, 3);
	}

	draw_particle_system(&blood_particle_system);

	when false {
		debug_line({0, 0, 0}, {50, 0, 0}, {1, 0, 0, 1});
		debug_line({0, 0, 0}, {0, 50, 0}, {0, 1, 0, 1});
		debug_line({0, 0, 0}, {0, 0, 50}, {0, 0, 1, 1});
	}

	//debug_cube(-1, 1, {1, 1, 1, 1});
	end_draw_3d();
}


update_score_multiplier :: proc(game: ^Game) {
	new := int(math.log(game.combo, 2))+1;
	if new > game.score_multiplier {
		game.score_multiplier = new;
	}
	else if game.combo == 0 {
		game.score_multiplier = 1;
	}
	else if new < game.score_multiplier-1 {
		game.score_multiplier = new;
	}
}
get_score_multiplier :: proc(game: ^Game) -> int {
	return game.score_multiplier;
}

do_game_gui :: proc(game: ^Game) {
	start_draw_2d();

	if game.display_score < game.score do game.display_score += 1;

	top_text_x_margin := f32(font.line_advance*1);
	top_text_top := f32(font.line_advance*0.5);
	draw_text(fmt.tprintf("Score: %d", game.display_score), &font, {top_text_x_margin, top_text_top}, .Left, .Top, {1, 0, 0, 1});

	multiplier := get_score_multiplier(game);
	if multiplier > 1 {
		draw_text(fmt.tprintf("X %d", multiplier), &font, {top_text_x_margin, top_text_top + font.line_advance}, .Left, .Top, {1, 0, 0, 1});
	}

	hp_max_width := get_text_draw_size("HP: 999 & 999", &font).x;
	draw_text(fmt.tprintf("HP: %d & %d", game.player_giant.feet[LEFT].hp, game.player_giant.feet[RIGHT].hp), &font, {window_size.x - top_text_x_margin - hp_max_width, top_text_top}, .Left, .Top, {1, 0, 0, 1});

	if !game.started {
		draw_text("Click to start", &font, window_size*0.5 + {0, font.line_advance*1.2}, .Center, .Center, {0.6, 0, 0, 1});
	}
	else if game.game_over_duration > GAME_OVER_FADE_IN_DURATION {
		draw_text("Game Over", &font, window_size*0.5, .Center, .Center, {0.6, 0, 0, 1});

		if game.game_over_duration > GAME_OVER_DURATION_BEFORE_RESTARTABLE {

			draw_text("Click to restart", &font, window_size*0.5 + {0, font.line_advance*1.2}, .Center, .Center, {0.6, 0, 0, 1});
		}
	}

	if !game.game_over {
		if game.player_giant.repair_mode_remaining_time > 0 {
			if math.mod(get_time()*2, 1) > 0.25 {
				draw_text("REPAIR MODE ACTIVE", &font, window_size*0.5, .Center, .Center, {1, 1, 0, 1});
			}
		}
		for foot in game.player_giant.feet {

			if foot.bigger_stomp_remaining_time > 0 {
				if math.mod(get_time()*2, 1) > 0.25 {
					draw_text("BIGGER STOMP ACTIVE", &font, window_size*0.5 + {0, font.line_advance*1.5}, .Center, .Center, {1, 0.2, 0, 1});
				}
				break;
			}
		}
	}

	if debug_text != "" do draw_text(debug_text, &font, {110, 300}, .Left, .Top, {0, 0, 1, 1});

	end_draw_2d();
}

app_tick_and_draw :: proc() {
	debug_text = "";
	//start_draw_frame({0.2, 0, 0.25});
	start_draw_frame({0.1, 0.1, 0.1});

	game_tick_and_draw(&app.game);
	do_game_gui(&app.game);

	end_draw_frame();
}