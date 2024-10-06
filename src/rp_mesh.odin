package main

import "core:fmt"
import "core:strings"
import "core:mem"

mesh_data_from_rp_mesh_data_version3 :: proc(reader: ^Byte_Buffer, debug_file_name: string) -> (result: Mesh_Data, ok: bool) {
	error_string: string;
	defer {
		if !ok {
			fmt.printf("Failed to read rp mesh. %s\n", error_string);
		}
	}
	want_uvs := true;
	want_normals := true;
	want_tangents := true;

	has_uvs := bb_read_type(reader, b8) or_return;
	has_uvs2 := bb_read_type(reader, b8) or_return;
	has_normals := bb_read_type(reader, b8) or_return;
	has_colors := bb_read_type(reader, b8) or_return;
	has_tangents := bb_read_type(reader, b8) or_return;

	vertex_count := bb_read_type(reader, u32) or_return;
	index_count := bb_read_type(reader, u32) or_return;
	sub_mesh_count := bb_read_type(reader, u32) or_return;
	if sub_mesh_count == 0 {
		error_string = "Sub mesh count can't be 0";
		return;
	}
	if sub_mesh_count > MAX_SUB_MESH_COUNT {
		error_string = fmt.tprintf("Too many sub meshes (%u), max supported is %u.", sub_mesh_count, MAX_SUB_MESH_COUNT);
		return;
	}

	for ii in 0..<sub_mesh_count-1 {
		result.sub_mesh_index_offsets[ii] = bb_read_type(reader, u32) or_return;
		if result.sub_mesh_index_offsets[ii] >= index_count {
			error_string = fmt.tprintf("Sub mesh index offset (%u) can't be >= index count (%u).", result.sub_mesh_index_offsets[ii], index_count);
			return;
		}
	}

	allocation_size: i64 = 0;
	material_names_alocation_offset: [MAX_SUB_MESH_COUNT]i64;
	for ii in 0..<sub_mesh_count {
		name_len := bb_read_type(reader, u8) or_return;
		if name_len > 0 {
			result.sub_mesh_material_names[ii] = strings.string_from_ptr(&reader.data[reader.cursor], cast(int)name_len);
			reader.cursor += cast(int)name_len+1;
			// TODO: Test if this works
			//fmt.printf("Sub mesh material name = '%s'\n", result.sub_mesh_material_names[ii]);
		}
		else {
			result.sub_mesh_material_names[ii] = ""; 
			//fmt.printf("Sub mesh does not have a material name\n");
		}
	}

	positions_allocation_offset : i64 = -1;
    uvs1_allocation_offset : i64 = -1;
    uvs2_allocation_offset : i64 = -1;
    normals_allocation_offset : i64 = -1;
    tangents_allocation_offset : i64 = -1;
    colors_allocation_offset : i64 = -1;
    indices_allocation_offset : i64 = -1;

    if(want_uvs && !has_uvs) {
        uvs1_allocation_offset = allocation_size;
        allocation_size += (i64)(size_of(result.uvs1[0]) * vertex_count);
    }
    if(want_normals && !has_normals) {
        normals_allocation_offset = allocation_size;
        allocation_size += (i64)(size_of(result.normals[0]) * vertex_count);
    }
    if(want_tangents && !has_tangents) {
        tangents_allocation_offset = allocation_size;
        allocation_size += (i64)(size_of(result.tangents[0]) * vertex_count);
    }

    memory: [^]u8;
    if allocation_size > 0 {
    	memory_p, alloc_error := mem.alloc(cast(int)allocation_size);
    	assert(alloc_error == .None);
    	memory = cast([^]u8)memory_p;
    	//fmt.printf("Allocate %d bytes\n", allocation_size);

    	if(positions_allocation_offset >= 0) {
            result.positions = cast([^]Vec3)(&memory[positions_allocation_offset]);
        }
        if(uvs1_allocation_offset >= 0) {
            result.uvs1 = cast([^]Vec2)(&memory[uvs1_allocation_offset]);
        }
        if(uvs2_allocation_offset >= 0) {
            result.uvs2 = cast([^]Vec2)(&memory[uvs2_allocation_offset]);
        }
        if(normals_allocation_offset >= 0) {
            result.normals = cast([^]Vec3)(&memory[normals_allocation_offset]);
        }
        if(tangents_allocation_offset >= 0) {
            result.tangents = cast([^]Vec4)(&memory[tangents_allocation_offset]);
        }
        if(colors_allocation_offset >= 0) {
            result.colors = cast([^]Vec3)(&memory[colors_allocation_offset]);
        }
        if(indices_allocation_offset >= 0) {
            result.indices = cast([^]Vertex_Index)(&memory[indices_allocation_offset]);
        }
    }
    result.allocation = memory;

    file_vertex_size: u64 = size_of(Vec3); // Always has positions
    if(has_uvs)      do file_vertex_size += size_of(Vec2);
    if(has_uvs2)     do file_vertex_size += size_of(Vec2);
    if(has_normals)  do file_vertex_size += size_of(Vec3);
    if(has_colors)   do file_vertex_size += size_of(Vec3);
    if(has_tangents) do file_vertex_size += size_of(Vec4);

    if(cast(u64)vertex_count * file_vertex_size + cast(u64)reader.cursor > cast(u64)len(reader.data)) {
        error_string = "Not enough bytes in file for vertex data";
        return;
    }

    // TODO: Endian flip
    result.positions = cast([^]Vec3)&reader.data[reader.cursor];
    reader.cursor += cast(int)(size_of(Vec3) * vertex_count);

    if has_uvs {
    	result.uvs1 = cast([^]Vec2)&reader.data[reader.cursor];
	    reader.cursor += cast(int)(size_of(Vec2) * vertex_count);
    }
    else if want_uvs {
    	mem.zero(result.uvs1, cast(int)(size_of(Vec2) * vertex_count));
    }

    if has_uvs2 {
    	result.uvs2 = cast([^]Vec2)&reader.data[reader.cursor];
	    reader.cursor += cast(int)(size_of(Vec2) * vertex_count);
    }

    if has_normals {
    	result.normals = cast([^]Vec3)&reader.data[reader.cursor];
	    reader.cursor += cast(int)(size_of(Vec3) * vertex_count);
    }
    else if want_normals {
    	// TODO: Calculate normals using triangle normals
    	for vi in 0..<vertex_count {
    		result.normals[vi] = {0, 0, 1};
    	}
    }
    if has_colors {
    	result.colors = cast([^]Vec3)&reader.data[reader.cursor];
	    reader.cursor += cast(int)(size_of(Vec3) * vertex_count);
    }
    
    if has_tangents {
    	result.tangents = cast([^]Vec4)&reader.data[reader.cursor];
	    reader.cursor += cast(int)(size_of(Vec4) * vertex_count);
    }

    if(cast(u64)index_count * size_of(u16) + cast(u64)reader.cursor > cast(u64)len(reader.data)) {
        error_string = "Not enough bytes in file for index data";
        return;
    }
    assert(size_of(result.indices[0]) == 2);
    result.indices = cast([^]Vertex_Index)&reader.data[reader.cursor];
    reader.cursor += cast(int)(size_of(u16) * index_count);

    if(!has_tangents && want_tangents) {
        //calculate_tangents(vertex_count, result.positions, result.uvs1, result.index_count, result.indices, result.tangents);
    }
    if(reader.cursor != len(reader.data)) {
        error_string = ("There are bytes remaining in the file when done.");
        return;
    }

    result.vertex_count = vertex_count;
    result.index_count = index_count;
    ok = true;
	return;
}

mesh_data_from_rp_mesh_data :: proc(data: []u8, debug_file_name: string) -> (mesh_data: Mesh_Data, ok: bool) {
	error_string: string;
	defer {
		if !ok {
			fmt.printf("Failed to read rp mesh. %s\n", error_string);

		}
	}
	reader := bb_create_reader(data);

	magic : [3]i8;
	bb_read_to_memory(&reader, &magic, 3) or_return;
	if magic[0] != 'r' || magic[1] != 'P' || magic[2] != 'm' {
		error_string = fmt.tprintf("Header magic mismatch, wanted 'rPm', got '%c%c%c'", magic[0], magic[1], magic[2]);
		return;
	}

	file_version := bb_read_type(&reader, u16) or_return;
	switch file_version {
		case 3: return mesh_data_from_rp_mesh_data_version3(&reader, debug_file_name);
		case: {
			error_string = fmt.tprintf("Unsupported file version %u", file_version);
			return;
		}
	}

	ok = true;
	return;
}