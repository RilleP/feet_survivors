package main

import "core:mem"

Byte_Buffer :: struct {
	data: []u8,
	cursor: int,
	allocator: mem.Allocator,
}

Byte_Buffer_Bookmark :: struct {
	cursor, size : int,
	type: typeid,
}

bb_create_reader :: proc(data: []u8) -> Byte_Buffer {
	return Byte_Buffer {
		data = data,
	};
}

bb_ensure_space :: proc(bb: ^Byte_Buffer, space: int) -> bool {
	new_len := len(bb.data);
	required_len := bb.cursor + space;
	for required_len > new_len {
		if new_len == 0 {
			new_len = 1024;
		}
		else {
			new_len *= 2;
		}		
	}
	if new_len > len(bb.data) {
		if bb.allocator.procedure == nil do bb.allocator = context.allocator;
		new_data, error := mem.resize_bytes(bb.data, new_len, 1, bb.allocator);
		if error != nil do return false;
		bb.data = new_data;
	}
	return true;
}

bb_remaining :: proc(bb: ^Byte_Buffer) -> int {
	return len(bb.data) - bb.cursor;
}

bb_write_at_bookmark :: proc(bb: ^Byte_Buffer, bm: Byte_Buffer_Bookmark, write: []u8) {
	assert(bm.cursor + bm.size <= len(bb.data));
	assert(bm.size == len(write));

	mem.copy(&bb.data[bm.cursor], &write[0], len(write));
}

bb_write :: proc(bb: ^Byte_Buffer, write: []u8) -> bool {
	bb_ensure_space(bb, len(write)) or_return;

	mem.copy(&bb.data[bb.cursor], &write[0], len(write));
	bb.cursor += len(write);
	return true;
}

bb_write_type :: proc(bb: ^Byte_Buffer, _value: $Type) -> bool {
	value := _value;
	return bb_write(bb, mem.byte_slice(&value, size_of(value)));
}


bb_write_array :: proc(bb: ^Byte_Buffer, array: [dynamic]$T) -> bool {
	item_count := len(array);
	if !bb_write_type(bb, item_count) do return false;
	if item_count > 0 {
		if !bb_write(bb, mem.byte_slice(&array[0], item_count * size_of(array[0]))) do return false;	
	}
	return true;
}

type_slice :: proc(pointer: ^$Type) -> []u8 {
	return mem.byte_slice(pointer, size_of(pointer^));
}

bb_push_bookmark :: proc(bb: ^Byte_Buffer, size: int) -> (result_bm: Byte_Buffer_Bookmark, success: bool) {
	
	bb_ensure_space(bb, size) or_return;

	defer bb.cursor += size;
	return Byte_Buffer_Bookmark { cursor = bb.cursor, size = size }, true;
}

bb_read_size :: proc(bb: ^Byte_Buffer, read_len: int) -> ([]u8, bool) {
	if bb.cursor + read_len > len(bb.data) {
		return mem.byte_slice(nil, 0), false;
	}

	defer bb.cursor += read_len;
	return bb.data[bb.cursor:bb.cursor+read_len], true;
}

bb_read_to_slice :: proc(bb: ^Byte_Buffer, dest: []u8) -> bool {
	return bb_read_to_memory(bb, raw_data(dest), len(dest));
}

bb_read_to_memory :: proc(bb: ^Byte_Buffer, dest: rawptr, read_len: int) -> bool {
	if bb.cursor + read_len > len(bb.data) {
		return false;
	}

	mem.copy(dest, &bb.data[bb.cursor], read_len);
	bb.cursor += read_len;
	return true;	
}

bb_read_type :: proc(bb: ^Byte_Buffer, $T: typeid) -> (result: T, success: bool) {
	data := bb_read_size(bb, size_of(T)) or_return;
	mem.copy(&result, &data[0], size_of(T));
	success = true;
	return;
}

bb_read_variable :: proc(bb: ^Byte_Buffer, pointer: ^$T) -> (success: bool) {
	pointer^, success = bb_read_type(bb, T);
	return;
}

bb_read_array :: proc(bb: ^Byte_Buffer, array_p: ^[dynamic]$T, allocator := context.allocator) -> bool {
	item_count := bb_read_type(bb, int) or_return;
	if bb_remaining(bb) / size_of(array_p[0]) < item_count do return false; // Check if enough bytes remaining in the file before allocating. Because item count might be really high if the file is old or corrupted.
	array_p^ = make([dynamic]T, item_count, allocator);
	if item_count > 0 {
		if !bb_read_to_memory(bb, &array_p[0], item_count*size_of(array_p[0])) do return false;
	}
	return true;
}

bb_read_cstring :: proc(bb: ^Byte_Buffer) -> (result: string, success: bool) {
	start := bb.cursor;
	for bb.cursor < len(bb.data) {
		defer bb.cursor += 1;
		if bb.data[bb.cursor] == 0 {
			return transmute(string)bb.data[start:bb.cursor], true;
		}
	}
	return "", false;
}