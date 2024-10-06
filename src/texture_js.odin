package main

import GL "../packages/wasm/WebGL"

texture_from_bitmap :: proc(bitmap: Bitmap, repeat: bool = false, filter: Texture_Filter = .Linear) -> (texture: Texture) {
	texture.width = bitmap.width;
	texture.height = bitmap.height;
	texture.id = u32(GL.CreateTexture());
	GL.BindTexture(GL.TEXTURE_2D, GL.Texture(texture.id));

	internal_format: GL.Enum;
	format: GL.Enum;
	switch bitmap.channels {
		case 1: 
			format = GL.RED;
			internal_format = GL.R8;
		case 2: 
			format = GL.RG;
			internal_format = GL.RG8;
		case 3: 
			format = GL.RGB;
			internal_format = GL.RGB;
		case 4: 
			format = GL.RGBA;
			internal_format = GL.RGBA;
		case: panic("Invalid number of channels of bitmap!!!");
	}

	GL.TexImage2D(GL.TEXTURE_2D, 0, internal_format, texture.width, texture.height, 0, format, GL.UNSIGNED_BYTE, int(texture.width*texture.height*bitmap.channels), bitmap.pixels);
	if(repeat) {
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, i32(GL.REPEAT));
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, i32(GL.REPEAT));
	}
	else {
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, i32(GL.CLAMP_TO_EDGE));
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, i32(GL.CLAMP_TO_EDGE));
	}
	switch filter {
		case .Nearest: {
			GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, i32(GL.NEAREST));
			GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, i32(GL.NEAREST));		
		}
		case .Linear: {
			GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, i32(GL.LINEAR));
			GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, i32(GL.LINEAR));
		}
	}
	
	GL.BindTexture(GL.TEXTURE_2D, 0);
	return texture;
}