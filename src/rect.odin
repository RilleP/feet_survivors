package main

Rect :: struct {
	min: Vec2,
	size: Vec2,
}

rect_contains :: proc(rect: Rect, p: Vec2) -> bool {
	return !(p.x < rect.min.x || 
			p.y < rect.min.y || 
			p.x > rect.min.x+rect.size.x || 
			p.y > rect.min.y+rect.size.y);
}