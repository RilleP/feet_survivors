package main

Bitmap :: struct {
	pixels: [^]u8,

	width, height, channels: i32,
	signed: bool,
}

Texture :: struct {
	id: u32,
	width, height: i32,
}

Texture_Filter :: enum {
	Nearest,
	Linear,
}

Sprite :: struct {
	texture: ^Texture,
	uv0, uv1: Vec2,
}

sprite_from_min_size_pixels :: proc(texture: ^Texture, x0, y0, w, h: int) -> Sprite {
	return Sprite {
		texture = texture,
		uv0 = {f32(x0) / f32(texture.width), f32(y0) / f32(texture.height)},
		uv1 = {f32(x0 + w) / f32(texture.width), f32(y0 + h) / f32(texture.height)},
	}
} 