package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "base:intrinsics"
import "core:time"
import "core:mem"
import "core:strings"
import "stb_image"

import "../packages/wasm/js" 
import GL "../packages/wasm/WebGL"

foreign import "js_font"
@(default_calling_convention="contextless")
foreign js_font {
	js_generate_font_texture :: proc(texture: u32, texture_dim: int, size: int, chars: string, glyphs: [^]GlyphInfo, one_glyph_data_size: int, font_descent, font_ascent: ^f32) -> int ---
}

foreign import "env"
@(default_calling_convention="contextless")
foreign env {
	//js_printf :: proc(str: string) ---
	log :: proc(string) ---
	log_int :: proc(int) ---
	us_now :: proc() -> int ---
	ms_now :: proc() -> f32 ---
	fetch_file :: proc(path: string) -> int ---
	is_file_fetching_done :: proc(index: int) -> bool ---
	get_fetched_file_length :: proc(index: int) -> int ---
	get_fetched_file_data :: proc(index: int, buffer: rawptr) ---	

	/*js_get_name :: proc(buffer: rawptr, max_length: int) -> int ---
	js_open_name_input :: proc(buffer: rawptr, max_length: int) -> int ---
	js_save_name :: proc(name: string) ---*/
	js_on_done_loading :: proc() ---
}

foreign import "audio"
@(default_calling_convention="contextless")
foreign audio {
	js_play_sound :: proc(path: string, volume: f32) ---
	platform_set_sound_volume :: proc(volume: f32) ---
	platform_set_music_volume :: proc(volume: f32) ---
}

play_sound :: proc(path: string, volume: f32 = 1.0) {
	v := volume * app.sound_volume;
	if v > 0 {
		js_play_sound(path, v);
	}
}


main_allocator : mem.Allocator;
temp_allocator : mem.Allocator;

start_time: int;
start_time_ms: f32;
prev_time_ms: f32;

WEB_PAGE_HEAD_SIZE :: 64; // Whatever as long as it fits
PAGE_SIZE :: js.PAGE_SIZE;

Web_Page :: struct {
	prev: ^Web_Page,
	used, cap: int,
}

allocated_page_count := 0;

web_allocator :: proc() -> mem.Allocator {
	push_page :: proc(min_size: int) -> ^Web_Page {
		page_count := math.max(1, (min_size+WEB_PAGE_HEAD_SIZE+PAGE_SIZE-1) / PAGE_SIZE)
		page_mem, err := js.page_alloc(page_count);
		assert(err == nil, "Failed to allocate pages for web_allocator");

		allocated_page_count += page_count;
		page := cast(^Web_Page)(&page_mem[0]);
		page.used = 0;
		page.cap = PAGE_SIZE*page_count - WEB_PAGE_HEAD_SIZE;
		page.prev = nil;
		return page;
	}

	procedure :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
	                  size, alignment: int,
	                  old_memory: rawptr, old_size: int,
	                  location := #caller_location) -> ([]byte, mem.Allocator_Error) {
		switch mode {
		case .Alloc, .Alloc_Non_Zeroed:
			assert(allocator_data != nil);
			//fmt.printf("Allocate %v bytes. %v\n", size, location);
			//assert(size <= PAGE_SIZE - WEB_PAGE_HEAD_SIZE); // TODO: Handle multipage allocations

			first_page := cast(^Web_Page)allocator_data;
			page : ^Web_Page;
			for pp := first_page; ; pp = pp.prev {
				aligned_used := mem.align_forward_int(pp.used, alignment);
				if pp.cap >= aligned_used + size {
					pp.used = aligned_used;
					page = pp;
					break;
				}

				if pp.prev == first_page || pp.prev == nil {
					page = nil;
					break;
				}
			}
			//page := first_page.prev != nil ? first_page.prev : first_page;

			if(page == nil) {
				new_page := push_page(size);
				assert(new_page != nil, "Failed to allocate page when growing web_allocator");

				new_page.prev = page;
				first_page.prev = new_page;

				//mem.copy(page, new_page, size_of(Web_Page));
				page = new_page;
				//log("Grew web page\n");
			} 

			assert(page.used + size <= page.cap);
			result := intrinsics.ptr_offset(cast(^u8)page, uintptr(WEB_PAGE_HEAD_SIZE + page.used));
			page.used += size;
			/*log("allocate bytes\n");
			log_int(size);*/
			if mode == .Alloc {
				mem.set(result, 0, size);
			}
			return mem.byte_slice(result, size), nil;
			//return js.page_alloc(size/PAGE_SIZE);
		case .Free_All: {
			assert(allocator_data != nil);
			
			first_page := cast(^Web_Page)allocator_data;
			for page := first_page; ; page = page.prev {
				page.used = 0;

				if page.prev == first_page || page.prev == nil {
					break;
				}
			}
			//log("Free all\n");
		}
		case .Resize_Non_Zeroed: {
			assert(false);
		}
		case .Resize: {
			first_page := cast(^Web_Page)allocator_data;
			page := first_page.prev != nil ? first_page.prev : first_page;
			
			end := intrinsics.ptr_offset(cast(^u8)page, uintptr(WEB_PAGE_HEAD_SIZE + page.used));
			old_alloc_end := intrinsics.ptr_offset(cast(^u8)old_memory, old_size);
			delta_size := size - old_size;
			/*if(delta_size < 0) {
				return mem.byte_slice()
			}
			else */if(end == old_alloc_end && (page.used + delta_size <= page.cap)) {
				//log("realloc continue\n");
				page.used += delta_size;
				return mem.byte_slice(intrinsics.ptr_offset(old_alloc_end, -old_size), size), nil;
			}
			else {
				//log("realloc new\n");
				result, err := procedure(allocator_data, .Alloc, size, alignment, nil, 0);
				assert(err == nil, "failed to realloc");
				if(old_memory != nil && old_size != 0) {
					mem.copy_non_overlapping(&result[0], old_memory, old_size);
				}
				return result, nil;
			}
		}
		case .Free, .Query_Info:
			return nil, .Mode_Not_Implemented;
		case .Query_Features:
			set := (^mem.Allocator_Mode_Set)(old_memory);
			if set != nil {
				set^ = {.Alloc, .Resize, .Query_Features};
			}
		}

		return nil, nil;
	}


	
	return {
		procedure = procedure,
		data = push_page(0),
	};
}

/*main :: proc() {

}*/

@export _start :: proc(is_mobile_device, enable_sound: bool) {
	app.is_touch_device = is_mobile_device;
	app.enable_sound = enable_sound;
	rand.reset(cast(u64)time.now()._nsec);
	start_time = us_now();
	start_time_ms = ms_now();
	prev_time_ms = start_time_ms;
	GL.CreateCurrentContextById("glcanvas", {});
	
	main_allocator = web_allocator();	
	temp_allocator = web_allocator();
	context.allocator = main_allocator;
	context.temp_allocator = temp_allocator;

	major, minor: i32;
	GL.GetWebGLVersion(&major, &minor);
	fmt.printf("GL Version %d.%d\n", major, minor);
	
	init_draw();

	window_width = GL.DrawingBufferWidth();
	window_height = GL.DrawingBufferHeight();
	window_size = {f32(window_width), f32(window_height)};	
	
	load_assets();

	js.add_window_event_listener(.Key_Down, nil, handle_key_event, true);
	js.add_window_event_listener(.Key_Up, nil, handle_key_event, true);

	if !is_mobile_device {
		js.add_event_listener("glcanvas", .Mouse_Down, nil, handle_mouse_up_down_event, true);
		js.add_event_listener("glcanvas", .Mouse_Up, nil, handle_mouse_up_down_event, true);
		js.add_event_listener("glcanvas", .Mouse_Move, nil, handle_mouse_move_event, true);
		js.add_event_listener("glcanvas", .Scroll, nil, handle_scroll_event, true);
		js.add_event_listener("glcanvas", .Wheel, nil, handle_wheel_event, true);
	}
	else {
		is_touch_screen = true;
		js.add_event_listener("glcanvas", .Touch_Start, nil, handle_touch_event, true);
		js.add_event_listener("glcanvas", .Touch_End, nil, handle_touch_event, true);
		js.add_event_listener("glcanvas", .Touch_Move, nil, handle_touch_event, true);
	}

	js.event_prevent_default();
	js.event_stop_immediate_propagation();
	js.event_stop_propagation();
}

left_ctrl_down := false;
left_shift_down := false;
right_ctrl_down := false;
right_shift_down := false;
handle_key_event :: proc(e: js.Event) {
	//log(e.key.key);
	//log(e.key.code);
	context.allocator = main_allocator;
	context.temp_allocator = temp_allocator;
	assert(e.kind == .Key_Down || e.kind == .Key_Up);
	pressed := e.kind == .Key_Down;


	switch(e.key.code) {
		case "ArrowLeft":  handle_move_key_event(pressed, e.key.repeat, false, .WEST);
		case "ArrowRight": handle_move_key_event(pressed, e.key.repeat, false, .EAST);
		case "ArrowUp":    handle_move_key_event(pressed, e.key.repeat, false, .NORTH);
		case "ArrowDown":  handle_move_key_event(pressed, e.key.repeat, false, .SOUTH);
		
		case "KeyA": handle_move_key_event(pressed, e.key.repeat, true, .WEST);
		case "KeyD": handle_move_key_event(pressed, e.key.repeat, true, .EAST);
		case "KeyW": handle_move_key_event(pressed, e.key.repeat, true, .NORTH);
		case "KeyS": handle_move_key_event(pressed, e.key.repeat, true, .SOUTH);

		case "ControlLeft":  left_ctrl_down = pressed;
		case "ControlRight": right_ctrl_down = pressed;
		case "ShiftLeft":    left_shift_down = pressed;
		case "ShiftRight":   right_shift_down = pressed;
		case "Backspace":    if pressed do inputted_text_count -= 1;
		case "Enter": {
			enter_is_pressed = pressed;
			if pressed {
				enter_got_pressed = true;
			}
		}
	}

	if pressed && len(e.key.key) == 1 && e.key.key[0] >= 32 && e.key.key[0] < 127 {
		inputted_text_buffer[inputted_text_count] = e.key.key[0];
		inputted_text_count += 1;
	}

}

handle_mouse_up_down_event :: proc(e: js.Event) {
	//log("Mouse down!\n");
	//log(e.id);
	//log_int(cast(int)e.mouse.page.x);
	//log_int(cast(int)e.mouse.page.y);

	mouse_window_p.x = i32(e.mouse.page.x);
	mouse_window_p.y = i32(e.mouse.page.y);
	mouse_p = linalg.array_cast(mouse_window_p, f32);
	//fmt.printf("Mouse button: %v\n", e.kind);
	if(e.mouse.button == 0) {
		left_mouse_is_down = e.kind == .Mouse_Down;
		if(left_mouse_is_down) {					
			left_mouse_got_pressed = true;
			touch_down_p = mouse_p;
		}
		else {
			left_mouse_got_released = true;
		}
	}
	else if e.mouse.button == 2 {
		right_mouse_is_down = e.kind == .Mouse_Down;
		if(right_mouse_is_down) {					
			right_mouse_got_pressed = true;
			touch_down_p = mouse_p;
		}
		else {
			right_mouse_got_released = true;
		}
	}
}

handle_mouse_move_event :: proc(e: js.Event) {
	//fmt.printf("Mouse %v\n", e.mouse);
	mouse_window_p.x = i32(e.mouse.page.x);
	mouse_window_p.y = i32(e.mouse.page.y);

	mouse_p = linalg.array_cast(mouse_window_p, f32);	
}

handle_scroll_event :: proc(e: js.Event) {
	mouse_scroll_amount += i32(e.scroll.delta.y*10);
}

handle_wheel_event :: proc(e: js.Event) {
	#partial switch e.kind {
		case .Wheel: {
			switch e.wheel.delta_mode {
				case .Pixel: mouse_scroll_amount -= i32(e.wheel.delta.y);
				case .Line: mouse_scroll_amount -= i32(e.wheel.delta.y);
				case .Page: mouse_scroll_amount -= i32(e.wheel.delta.y*f64(window_height));
			}
		}
		case .Mouse_Move: {
			fmt.printf("Got mouse move event in handle wheel????????\n");
		}
		case: {
			fmt.printf("Got unexpected event %v in handle wheel?????\n", e.kind);
		}
	}
	
}

handle_touch_event :: proc(e: js.Event) {
	#partial switch e.kind {
		case .Touch_Start: {
			//fmt.printf("Touch started %v\n", e.touch);
			left_mouse_got_pressed = true;
			left_mouse_is_down = true;

			mouse_window_p.x = i32(e.touch.client.x);
			mouse_window_p.y = i32(e.touch.client.y);
			mouse_p = linalg.array_cast(mouse_window_p, f32);
			touch_down_p = mouse_p;
			touch_delta_p = {};
			is_dragging = false;
		}
		case .Touch_End: {
			//fmt.printf("Touch ended %v\n", e.touch);
			left_mouse_is_down = false;
			left_mouse_got_released = true;

			touch_delta_p = {};
		}
		case .Touch_Move: {
			//fmt.printf("Touch moved %v\n", e.touch);
			mouse_window_p.x = i32(e.touch.client.x);
			mouse_window_p.y = i32(e.touch.client.y);
			new_mouse_p := linalg.array_cast(mouse_window_p, f32);
			touch_delta_p += new_mouse_p - mouse_p;
			mouse_p = new_mouse_p;
		}
		case: {
			fmt.printf("Unhandled touch event %v\n", e.kind);
		}
	}
}

load_file :: proc(type: File_Type, path: string) -> ^Fetching_File {
	assert(file_queue_count < len(file_queue));


	result := &file_queue[file_queue_count];
	file_queue_count += 1;

	result.index = fetch_file(path);
	result.type = type;
	result.debug_path = strings.clone(path);

	return result;
}

load_texture :: proc(path: string, texture: ^Texture, repeat := false, filter := Texture_Filter.Linear, channels := 4) {
	file := load_file(.TEXTURE, path);

	file.texture = texture;
	file.texture_repeat = repeat;
	file.texture_filter = filter;
	file.texture_channels = channels;
}

load_bitmap :: proc(path: string, bitmap: ^Bitmap) {
	file := load_file(.BITMAP, path);
	file.bitmap = bitmap;
}

file_queue: [128]Fetching_File;
file_queue_count: int = 0;

File_Type :: enum {
	TEXTURE,
	BITMAP,
	//LEVEL,
	//PLAYLIST,
}

Fetching_File :: struct {
	index: int,	
	type: File_Type,
	texture: ^Texture,
	texture_repeat: bool,
	texture_filter: Texture_Filter,
	texture_channels: int,
	bitmap: ^Bitmap,
	data_target: ^File_Data,
	debug_path: string,
}


@export _end :: proc() {

}

handle_fetched_file :: proc(ff: ^Fetching_File, buffer: []u8) {
	switch(ff.type) {
		case .TEXTURE: {
			assert(ff.texture != nil);
			width, height, channels_in_file: int;
			channels := ff.texture_channels;
			pixels := stb_image.stbi_load_png_from_memory(buffer, &width, &height, &channels_in_file, channels);

			if pixels == nil {
				log("Failed to load texture!\n");
				log(ff.debug_path);

				gen_pixels := make([]u8, width*height*channels, context.temp_allocator);
				for yy in 0..<height {
					for xx in 0..<width {
						gen_pixels[(xx + yy * width)*channels + 0] = cast(u8)(xx*255/width); 
						gen_pixels[(xx + yy * width)*channels + 1] = cast(u8)(yy*255/height); 
						gen_pixels[(xx + yy * width)*channels + 2] = xx > width/2 ? 255 : 0; 
						gen_pixels[(xx + yy * width)*channels + 3] = 255;
					}
				}
				pixels = raw_data(gen_pixels[:]);
			}
			else {
				texture := GL.CreateTexture();
				ff.texture^ = {
					id = cast(u32)texture,
					width = cast(i32)width,
					height = cast(i32)height,
				};

				GL.BindTexture(GL.TEXTURE_2D, texture);

				format := GL.RGBA;
				internal_format := GL.RGBA;
				if channels == 1 {
					format = GL.RED;
					internal_format = GL.R8;
				}
				GL.TexImage2D(GL.TEXTURE_2D, 0, internal_format, cast(i32)width, cast(i32)height, 0, format, GL.UNSIGNED_BYTE, int(width*height*channels), pixels);
				wrap := ff.texture_repeat ? i32(GL.REPEAT) : i32(GL.CLAMP_TO_EDGE);
				GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, wrap);
				GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, wrap);
				switch ff.texture_filter {
					case .Nearest: {
						GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, i32(GL.NEAREST));
						GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, i32(GL.NEAREST));		
					}
					case .Linear: {
						GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, i32(GL.LINEAR));
						GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, i32(GL.LINEAR));
					}
				}
			}
		}
		case .BITMAP: {
			assert(ff.bitmap != nil);
			width, height, channels_in_file: int;
			channels := 4;
			pixels := stb_image.stbi_load_png_from_memory(buffer, &width, &height, &channels_in_file, channels);

			if pixels == nil {
				fmt.printf("Failed to load bitmap: %s!\n", ff.debug_path);
			}
			else {
				ff.bitmap^ = {
					pixels = cast([^]u8)pixels,
					width = cast(i32)width,
					height = cast(i32)height,
				};
			}
		}	
	}
}


font_chars_string: string;

update_font :: proc() {
	new_font_size := compute_font_size();
	if math.abs(new_font_size - font.size) < 2 {
		return;
	}
	font.size = new_font_size;

	//font.line_height = font.size;
	//font.line_advance = font.line_height*1.2;

	FONT_TEXTURE_DIM :: 1024;
	if font.texture.id == 0 {
		font.texture = {
			id = cast(u32)GL.CreateTexture(),
			width = FONT_TEXTURE_DIM,
			height = FONT_TEXTURE_DIM,
		};

	}
	if font.glyphs == nil {
		font.first_char = 31;
		font.last_char = 127;
		chars := make([]byte, int(font.last_char-font.first_char + 1));
		for ci in 0..<len(chars) {
			chars[ci] = byte(font.first_char + ci);
		}
		font_chars_string = transmute(string)chars;
		font.glyphs = make([]GlyphInfo, len(font_chars_string));
	}
	js_generate_font_texture(font.texture.id, FONT_TEXTURE_DIM, int(font.size), font_chars_string, raw_data(font.glyphs), size_of(GlyphInfo), &font.descent, &font.ascent);
	font.space_xadvance = font.glyphs[' '-font.first_char].xadvance;
	font.line_height = font.ascent - font.descent;
	font.line_advance = font.line_height * 1.2;
}

app_initialized := false;
@export step :: proc(dt_arg: f32) {
	context.allocator = main_allocator;
	context.temp_allocator = temp_allocator;
	context.random_generator = rand.default_random_generator();
	mem.free_all(temp_allocator);

	for ii := 0; ii < file_queue_count; ii += 1 {
		ff := &file_queue[ii];

		if is_file_fetching_done(ff.index) {

			length := get_fetched_file_length(ff.index);
			buffer := make([]u8, length, context.temp_allocator);
			get_fetched_file_data(ff.index, raw_data(buffer[:]));

			handle_fetched_file(ff, buffer);

			file_queue_count -= 1;
			if ii < file_queue_count {
				file_queue[ii] = file_queue[file_queue_count];
				ii -= 1;
			}
		}
	}
	if(file_queue_count > 0) {
		/*window_width := GL.DrawingBufferWidth();
		window_height := GL.DrawingBufferHeight();
		LOADING := "Loading...";
		js_draw_text(LOADING, 20, f32(window_width)*0.5, f32(window_height)*0.5, int(Align_X.Center), int(Align_Y.Center), 1, 1, 1, 1);*/
		return;
	}

	if !app_initialized {
		fmt.printf("Fetched all files in %0.2fms\n", ms_now());
		timer := timer_start();
		app_init();
		fmt.printf("Init app in %0.2fms\n", timer_elapsed_ms(timer));
		app_initialized = true;
		

		window_width = GL.DrawingBufferWidth();
		window_height = GL.DrawingBufferHeight();
		window_size = {f32(window_width), f32(window_height)};
		
		update_font();

		js_on_done_loading();
	}

	new_window_width := GL.DrawingBufferWidth();
	new_window_height := GL.DrawingBufferHeight();
	if new_window_width != window_width || new_window_height != window_height {
		window_width = new_window_width;
		window_height = new_window_height;
		window_size = {f32(window_width), f32(window_height)};
		update_font();
	}

	dt = math.min(dt_arg, 1.0/30.0);
	mouse_delta = mouse_p - last_mouse_p;
	last_mouse_p = mouse_p;


	app_tick_and_draw();

	left_mouse_got_pressed = false;
	left_mouse_got_released = false;
	if !left_mouse_is_down {
		is_dragging = false;
	}
	right_mouse_got_pressed = false;
	right_mouse_got_released = false;
	mouse_scroll_amount = 0;
	touch_delta_p = {}
	inputted_text_count = 0;
	enter_got_pressed = false;
}


get_time :: proc() -> f32 {
	return ms_now()*0.001;
}

Timer :: struct {
	start_ms: f32,
}

timer_start :: proc() -> Timer {
	return {
		start_ms = ms_now(),
	};
}

timer_elapsed :: proc(timer: Timer) -> f32 {
	return timer_elapsed_ms(timer) * 0.001;	
}

timer_elapsed_ms :: proc(timer: Timer) -> f32 {
	t := ms_now() - timer.start_ms;
	return t;
}

timer_restart :: proc(timer: ^Timer) -> f32 {
	now := ms_now();
	t := now - timer.start_ms;
	timer.start_ms = now;
	return t;
}