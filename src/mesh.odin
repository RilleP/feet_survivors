package main

Vertex_Index :: u16;
MESH_MAX_VERTEX_COUNT :: 0xffff;

MAX_SUB_MESH_COUNT :: 16;

Vertex_Attribute :: enum {
    POSITION,
    UV1,
    UV2,
    NORMAL,
    TANGENT,
    COLOR,
}

Mesh_Data :: struct {
	vertex_count, index_count: u32,
	positions: [^]Vec3,
	uvs1: [^]Vec2,
	uvs2: [^]Vec2,
	normals: [^]Vec3,
	tangents: [^]Vec4,
	colors: [^]Vec3,
	indices: [^]Vertex_Index,
	sub_mesh_index_offsets: [MAX_SUB_MESH_COUNT-1]u32,
	sub_mesh_material_names: [MAX_SUB_MESH_COUNT]string,
	allocation: rawptr,
}

Mesh :: struct {
	vertex_buffer, index_buffer: u32,

	vertex_count, index_count: u32,
	positions: [^]Vec3,
	uvs1: [^]Vec2,
	uvs2: [^]Vec2,
	normals: [^]Vec3,
	tangents: [^]Vec4,
	colors: [^]Vec3,
	bone_indices: [^][4]u8,
	bone_weights: [^]Vec4,
	indices: [^]Vertex_Index,
	sub_mesh_index_offsets: [MAX_SUB_MESH_COUNT-1]u32,
	sub_mesh_material_names: [MAX_SUB_MESH_COUNT]string,
	
}

calculate_mesh_single_vertex_size :: proc(mesh: ^Mesh) -> u32 {
    single_vertex_size : u32 = size_of(mesh.positions[0]);
    if mesh.uvs1         != nil do single_vertex_size += size_of(mesh.uvs1[0]);
    if mesh.uvs2         != nil do single_vertex_size += size_of(mesh.uvs2[0]);
    if mesh.normals      != nil do single_vertex_size += size_of(mesh.normals[0]);
    if mesh.tangents     != nil do single_vertex_size += size_of(mesh.tangents[0]);
    if mesh.colors       != nil do single_vertex_size += size_of(mesh.colors[0]);
    if mesh.bone_indices != nil do single_vertex_size += size_of(mesh.bone_indices[0]);
    if mesh.bone_weights != nil do single_vertex_size += size_of(mesh.bone_weights[0]);
    return single_vertex_size;
}

VertexAttributeOffsets :: struct {
	position, uv1, uv2, normal, tangent, color, bone_indices, bone_weights: int,
}

mesh_get_vertex_attribute_offsets :: proc(mesh: ^Mesh, result: ^VertexAttributeOffsets) {

    offset: int = 0;

    result.position = offset;
    offset += cast(int)(size_of(Vec3) * mesh.vertex_count);

    if(mesh.uvs1 != nil) {
        result.uv1 = offset;
        offset += cast(int)(size_of(Vec2) * mesh.vertex_count);
    }
    else {
        result.uv1 = 0; 
    }
    if(mesh.uvs2 != nil) {
        result.uv2 = offset;
        offset += cast(int)(size_of(Vec2) * mesh.vertex_count);
    }
    else do result.uv2 = 0;

    if(mesh.normals != nil) {
        result.normal = offset;
        offset += cast(int)(size_of(Vec3) * mesh.vertex_count);   
    }
    else do result.normal = 0;

    if(mesh.tangents != nil) {
        result.tangent = offset;
        offset += cast(int)(size_of(Vec4) * mesh.vertex_count);   
    }
    else do result.tangent = 0;

    if(mesh.colors != nil) {
        result.color = offset;
        offset += cast(int)(size_of(Vec3) * mesh.vertex_count);   
    }
    else do result.color = 0;

    if(mesh.bone_indices != nil) {
        result.bone_indices = offset;
        offset += cast(int)(size_of(mesh.bone_indices[0]) * mesh.vertex_count);
    }
    else do result.bone_indices = 0;

    if(mesh.bone_weights != nil) {
        result.bone_weights = offset;
        offset += cast(int)(size_of(mesh.bone_weights[0]) * mesh.vertex_count);
    }

    /*if(mesh.custom_vdata.data != nil) {
        result.custom_vdata = offset;
        offset += vertex_data_type_size[mesh.custom_vdata.type]*mesh.custom_vdata.component_count;
    }
    else result.custom_vdata = 0;*/
}

mesh_from_mesh_data :: proc(mesh_data: ^Mesh_Data) -> (result: Mesh) {
	

    result = {
    	vertex_count = mesh_data.vertex_count,
    	index_count = mesh_data.index_count,
    	positions = mesh_data.positions,
    	uvs1 = mesh_data.uvs1,
    	uvs2 = mesh_data.uvs2,
    	normals = mesh_data.normals,
    	tangents = mesh_data.tangents,
    	colors = mesh_data.colors,
    	indices = mesh_data.indices,
    	sub_mesh_index_offsets = mesh_data.sub_mesh_index_offsets,
    	sub_mesh_material_names = mesh_data.sub_mesh_material_names,
    }
	
    mesh_create(&result);
	return;
}

mesh_create :: proc(mesh: ^Mesh) {
    //GL.GenBuffers(1, &mesh.vertex_buffer);
    //GL.GenBuffers(1, &mesh.index_buffer);
	upload_mesh(mesh);
}


/*set_skinned_mesh :: proc(mesh: ^Mesh) {
    GL.BindBuffer(GL.ARRAY_BUFFER, mesh.vertex_buffer);
    offsets: VertexAttributeOffsets;
    mesh_get_vertex_attribute_offsets(mesh, &offsets);

    GL.EnableVertexAttribArray(0);
    GL.VertexAttribPointer(0, 3, GL.FLOAT, GL.FALSE, 0, cast(uintptr)offsets.position);

    GL.EnableVertexAttribArray(2);
    GL.VertexAttribPointer(2, 2, GL.FLOAT, GL.FALSE, 0, cast(uintptr)offsets.uv1);

    GL.EnableVertexAttribArray(4);
    GL.VertexAttribPointer(4, 3, GL.FLOAT, GL.FALSE, 0, cast(uintptr)offsets.normal);

    GL.EnableVertexAttribArray(6);
    GL.VertexAttribPointer(6, 3, GL.FLOAT, GL.FALSE, 0, cast(uintptr)offsets.color);

    GL.EnableVertexAttribArray(7);
    GL.VertexAttribIPointer(7, 4, GL.UNSIGNED_BYTE, 0, cast(uintptr)offsets.bone_indices);

    GL.EnableVertexAttribArray(8);
    GL.VertexAttribPointer(8, 4, GL.FLOAT, GL.FALSE, 0, cast(uintptr)offsets.bone_weights);
    
    GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, mesh.index_buffer);
}*/

/*draw_skinned_mesh :: proc(mesh: ^Mesh) {
    set_skinned_mesh(mesh);
    draw_active_mesh_index_range(mesh, 0, mesh.index_count);
}*/

draw_mesh :: proc(mesh: ^Mesh) {
	set_mesh(mesh);
	draw_active_mesh_index_range(mesh, 0, mesh.index_count);	
}