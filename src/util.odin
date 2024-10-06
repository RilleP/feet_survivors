package main

import "core:math"

v3_v2 :: proc(v: Vec2, z: f32 = 0) -> Vec3 {
	return {v.x, v.y, z};
}

z_rotation_to_vector :: proc(radians: f32) -> Vec3 {
	return Vec3{math.cos(radians), math.sin(radians), 0};
}

vector_to_z_rotation :: proc(v: Vec2) -> f32 {
	return math.atan2(v.y, v.x);
}

transform_point :: proc(p: Vec3, transform: Matrix4) -> Vec3 {
	return (transform * Vec4{p.x, p.y, p.z, 1}).xyz;
}

transform_point2d :: proc(p: Vec2, transform: Matrix4) -> Vec3 {
	return (transform * Vec4{p.x, p.y, 0, 1}).xyz;
}

transform_vector :: proc(v: Vec3, transform: Matrix4) -> Vec3 {
	return (transform * Vec4{v.x, v.y, v.z, 0}).xyz;
}

square :: proc(t: f32) -> f32 {
	return t*t;
}
inverse_square :: proc(t: f32) -> f32 {
	return 1 - square(1-t);
}
cube :: proc(t: f32) -> f32 {
	return t*t*t;
}
inverse_cube :: proc(t: f32) -> f32 {
	return 1 - cube(1-t);
}

vec2_rotate :: proc(v: Vec2, cw: bool) -> Vec2 {
	if cw do return vec2_rotate_cw(v);
	else do return vec2_rotate_ccw(v);
}

vec2_rotate_cw :: proc(v: Vec2) -> Vec2 {
	return {-v.y, v.x};
}

vec2_rotate_ccw :: proc(v: Vec2) -> Vec2 {
	return {v.y, -v.x};
}