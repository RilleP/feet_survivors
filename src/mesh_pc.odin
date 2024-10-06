#+build windows
package main

OPENGL_VERTEX_INDEX_TYPE :: GL.UNSIGNED_SHORT;

import GL "vendor:OpenGL"

upload_vertex_data :: proc(mesh: ^Mesh) {
    offsets : VertexAttributeOffsets;
    mesh_get_vertex_attribute_offsets(mesh, &offsets);

    GL.BufferSubData(GL.ARRAY_BUFFER, offsets.position, cast(int)(size_of(mesh.positions[0]) * mesh.vertex_count), mesh.positions);

    if(mesh.uvs1 != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.uv1, cast(int)(size_of(mesh.uvs1[0]) * mesh.vertex_count), mesh.uvs1);
    }

    if(mesh.uvs2 != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.uv2, cast(int)(size_of(mesh.uvs2[0]) * mesh.vertex_count), mesh.uvs2);
    }

    if(mesh.normals != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.normal, cast(int)(size_of(mesh.normals[0]) * mesh.vertex_count), mesh.normals);
    }

    if(mesh.tangents != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.tangent, cast(int)(size_of(mesh.tangents[0]) * mesh.vertex_count), mesh.tangents);
    }

    if(mesh.colors != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.color, cast(int)(size_of(mesh.colors[0]) * mesh.vertex_count), mesh.colors);
    }

    if(mesh.bone_indices != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.bone_indices, cast(int)(size_of(mesh.bone_indices[0]) * mesh.vertex_count), mesh.bone_indices);
    }

    if(mesh.bone_weights != nil) {
        GL.BufferSubData(GL.ARRAY_BUFFER, offsets.bone_weights, cast(int)(size_of(mesh.bone_weights[0]) * mesh.vertex_count), mesh.bone_weights);
    }
}

upload_mesh :: proc(mesh: ^Mesh) {
    assert(mesh.positions != nil);
    assert(mesh.vertex_count <= MESH_MAX_VERTEX_COUNT);

    single_vertex_size := calculate_mesh_single_vertex_size(mesh);
    
    //calculate_bounds(mesh);

    GL.GenBuffers(1, &mesh.vertex_buffer);
    GL.GenBuffers(1, &mesh.index_buffer);

    GL.BindBuffer(GL.ARRAY_BUFFER, mesh.vertex_buffer);
    
    vertex_buffer_size := single_vertex_size * mesh.vertex_count;

    GL.BufferData(GL.ARRAY_BUFFER, cast(int)vertex_buffer_size, nil, GL.STATIC_DRAW);

    upload_vertex_data(mesh);

    GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, mesh.index_buffer);
    GL.BufferData(GL.ELEMENT_ARRAY_BUFFER, cast(int)(size_of(mesh.indices[0]) * mesh.index_count), mesh.indices, GL.STATIC_DRAW);
}

set_mesh :: proc(mesh: ^Mesh) {
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
	
	GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, mesh.index_buffer);
}

draw_active_mesh_index_range :: proc(mesh: ^Mesh, index_offset, index_count: u32) {
    GL.DrawElements(GL.TRIANGLES, cast(i32)index_count, OPENGL_VERTEX_INDEX_TYPE, cast(rawptr)cast(uintptr)(size_of(mesh.indices[0])*index_offset));
}

draw_active_mesh :: proc(mesh: ^Mesh) {
    GL.DrawElements(GL.TRIANGLES, cast(i32)mesh.index_count, OPENGL_VERTEX_INDEX_TYPE, nil);
}