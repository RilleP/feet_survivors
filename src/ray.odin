package main

import "core:math"
import "core:math/linalg"

RAY_CAST_EPSILON :: f32(0.001);

Ray :: struct {
	origin, direction: Vec3,
}

ray_get_position :: #force_inline proc(ray: Ray, t: f32) -> Vec3 {
	return ray.origin + ray.direction*t;
}

ray_hit_plane :: proc(ray: Ray, plane_p, plane_n: Vec3, epsilon := RAY_CAST_EPSILON) -> (hit_t: f32, did_hit: bool) {
	denom := linalg.dot(plane_n, ray.direction);

	if denom < -epsilon {
		origin_diff := plane_p - ray.origin;
		hit_t = linalg.dot(origin_diff, plane_n) / denom;
		did_hit = hit_t >= 0;
	}
	return;
}

vec3_equal_eps :: #force_inline proc(a, b: Vec3, epsilon := f32(0.0001)) -> bool {
	diff := a-b;
	return math.abs(diff.x) < epsilon && 
		   math.abs(diff.y) < epsilon &&
		   math.abs(diff.z) < epsilon;
}

ray_hit_triangle :: proc(ray: Ray, v0, v1, v2: Vec3) -> (hit_t: f32, did_hit: bool) {
	epsilon := f32(0.0001);
	normal := linalg.normalize0(linalg.cross(v1-v0, v2-v0));

	t, did_hit_plane := ray_hit_plane(ray, v0, normal);
	if !did_hit_plane do return; 

	p := ray_get_position(ray, t);
	c: Vec3; // vector perpendicular to triangle's plane 

    edge0 := v1-v0;
    vp0 := p - v0; 
    c = linalg.normalize(linalg.cross(edge0, vp0)); 
    if (!vec3_equal_eps(c, 0, epsilon) && linalg.dot(normal, c) < 0) do return; // P is on the right side 
 
    // edge 1
    edge1 := v2 - v1; 
    vp1 := p - v1; 
    c = linalg.normalize(linalg.cross(edge1, vp1)); 
    if (!vec3_equal_eps(c, 0, epsilon) && linalg.dot(normal, c) < 0) do return; // P is on the right side 
 
    // edge 2
    edge2 := v0 - v2; 
    vp2   := p - v2; 
    c = linalg.normalize(linalg.cross(edge2, vp2)); 
    if (!vec3_equal_eps(c, 0, epsilon) && linalg.dot(normal, c) < 0) do return; // P is on the right side; 
 
    hit_t = t;
    return t, true; // this ray hits the triangle 
}