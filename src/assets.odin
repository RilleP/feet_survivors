package main

import "core:fmt"
import "core:math/linalg"
import "stb_image"

foot_left_mesh: Mesh;
foot_right_mesh: Mesh;
foot_texture: Texture;
creature1_mesh: Mesh;
floor_tile_mesh: Mesh;
floor_texture: Texture;
floor_texture_cracked: [2]Texture;
blood_mask: Texture;
cracked_floor: Mesh;

cracked_floor_parts: [13]Mesh;

heal_mesh: Mesh;
wrench_mesh: Mesh;
bigger_stomp_mesh: Mesh;

//FLOOR_TILING_PER_QUAD :: 32;
FLOOR_TILING_PER_QUAD :: 1;

load_assets :: proc() {
	foot_left_mesh = load_mesh_from_file("../res/foot_left.mesh");
	foot_right_mesh = load_mesh_from_file("../res/foot_right.mesh");
	foot_texture = load_texture_from_file("../res/foot_texture.png");
	creature1_mesh = load_mesh_from_file("../res/creature1.mesh");

	floor_tile_mesh = create_quad_mesh({1, 1}, {0, 0, 1}, {0, 1, 0}, 0, FLOOR_TILING_PER_QUAD);

	floor_texture = load_texture_from_file("../res/floor_single.png");
	floor_texture_cracked[0] = load_texture_from_file("../res/floor_single_cracked0.png");
	floor_texture_cracked[1] = load_texture_from_file("../res/floor_single_cracked1.png");

	blood_mask = load_texture_from_file("../res/blood_mask.png");

	cracked_floor = load_mesh_from_file("../res/cracked.mesh");
	fmt.println(cracked_floor.sub_mesh_index_offsets);

	cracked_floor_parts[0] = load_mesh_from_file("../res/cracked1.mesh");
	cracked_floor_parts[1] = load_mesh_from_file("../res/cracked2.mesh");
	cracked_floor_parts[2] = load_mesh_from_file("../res/cracked3.mesh");
	cracked_floor_parts[3] = load_mesh_from_file("../res/cracked4.mesh");
	cracked_floor_parts[4] = load_mesh_from_file("../res/cracked5.mesh");
	cracked_floor_parts[5] = load_mesh_from_file("../res/cracked6.mesh");
	cracked_floor_parts[6] = load_mesh_from_file("../res/cracked7.mesh");
	cracked_floor_parts[7] = load_mesh_from_file("../res/cracked8.mesh");
	cracked_floor_parts[8] = load_mesh_from_file("../res/cracked9.mesh");
	cracked_floor_parts[9] = load_mesh_from_file("../res/cracked10.mesh");
	cracked_floor_parts[10] = load_mesh_from_file("../res/cracked11.mesh");
	cracked_floor_parts[11] = load_mesh_from_file("../res/cracked12.mesh");
	cracked_floor_parts[12] = load_mesh_from_file("../res/cracked13.mesh");

	heal_mesh = load_mesh_from_file("../res/heal.mesh");
	wrench_mesh = load_mesh_from_file("../res/wrench.mesh");
	bigger_stomp_mesh = load_mesh_from_file("../res/bigger_stomp.mesh");
}




load_mesh :: proc(data: []u8, debug_name := #caller_expression) -> Mesh {
	foot_left_mesh_data, ok := mesh_data_from_rp_mesh_data(data, debug_name);
	if !ok {
		fmt.println("Failed to load mesh ", debug_name);
		return {};
	}
	return mesh_from_mesh_data(&foot_left_mesh_data);
}

load_mesh_from_file :: proc($file_path: string) -> Mesh {
	data :: #load(file_path, []u8);

	return load_mesh(data, file_path);
}

/*load_texture_from_data :: proc($data: []u8) -> Texture {

}*/

load_texture_from_file :: proc($file_path: string) -> Texture {
	data :: #load(file_path, []u8);


	bitmap: Bitmap;
	width, height: int;
	pixels := cast([^]u8)stb_image.stbi_load_png_from_memory(data, &width, &height, nil, 4);
	pixels2 := make([]u8, width*height*4);
	for xx in 0..<width {
		for yy in 0..<height {
			ii := (xx + yy * width)*4;
			jj := (xx + (height-yy)*width)*4;

			pixels2[ii+0] = pixels[jj+0];
			pixels2[ii+1] = pixels[jj+1];
			pixels2[ii+2] = pixels[jj+2];
			pixels2[ii+3] = pixels[jj+3];
		}
	}

	bitmap.pixels = &pixels2[0];
	bitmap.width = i32(width);
	bitmap.height = i32(height);
	bitmap.channels = 4;


	return texture_from_bitmap(bitmap, repeat = true);
}

create_quad_mesh :: proc(size: Vec2, normal: Vec3, forward: Vec3, min_uv: Vec2, max_uv: Vec2) -> Mesh {
	//side := linalg.cross(normal, forward);

	transform := linalg.matrix4_look_at_f32({0, 0, 0}, normal, -forward, true);

	md := allocate_mesh_data(4, 6, {.POSITION, .UV1, .NORMAL});
	r := size*0.5;
	md.positions[0] = transform_point({-r.x, +r.y, 0}, transform);
	md.positions[1] = transform_point({+r.x, +r.y, 0}, transform);
	md.positions[2] = transform_point({+r.x, -r.y, 0}, transform);
	md.positions[3] = transform_point({-r.x, -r.y, 0}, transform);

	md.uvs1[0] = {min_uv.x, min_uv.y};
	md.uvs1[1] = {max_uv.x, min_uv.y};
	md.uvs1[2] = {max_uv.x, max_uv.y};
	md.uvs1[3] = {min_uv.x, max_uv.y};

	for vi in 0..<md.vertex_count {
		md.normals[vi] = normal;
	}

	md.indices[0] = 0;
	md.indices[1] = 1;
	md.indices[2] = 2;

	md.indices[3] = 0;
	md.indices[4] = 2;
	md.indices[5] = 3;

	return mesh_from_mesh_data(&md);
}



allocate_mesh_data :: proc(vertex_count, index_count: u32, attributes: bit_set[Vertex_Attribute]) -> Mesh_Data {

	md : Mesh_Data = {
		vertex_count = vertex_count, index_count = index_count,
	}
	one_vertex_size: int;
	if .POSITION in attributes do one_vertex_size += size_of(md.positions[0]);
	if .UV1      in attributes do one_vertex_size += size_of(md.uvs1[0]);
	if .UV2      in attributes do one_vertex_size += size_of(md.uvs2[0]);
	if .NORMAL   in attributes do one_vertex_size += size_of(md.normals[0]);
	if .TANGENT  in attributes do one_vertex_size += size_of(md.tangents[0]);
	if .COLOR    in attributes do one_vertex_size += size_of(md.colors[0]);

	data := make([]u8, one_vertex_size*int(vertex_count) + size_of(Vertex_Index)*int(index_count));

	md.allocation = raw_data(data);

	take_array :: proc(data: ^[]u8, dest: ^[^]$T, count: u32) {
		dest^ = auto_cast &(data^)[0];
		data^ = (data^)[count * size_of(T):];
	}

	if .POSITION in attributes do take_array(&data, &md.positions, vertex_count);
	if .UV1      in attributes do take_array(&data, &md.uvs1, vertex_count);
	if .UV2      in attributes do take_array(&data, &md.uvs2, vertex_count);
	if .NORMAL   in attributes do take_array(&data, &md.normals, vertex_count);
	if .TANGENT  in attributes do take_array(&data, &md.tangents, vertex_count);
	if .COLOR    in attributes do take_array(&data, &md.colors, vertex_count);

	take_array(&data, &md.indices, index_count);

	return md;
}