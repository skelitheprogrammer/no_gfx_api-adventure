package main

import "base:intrinsics"
import "core:math/linalg"
import "core:mem"
import "gpu/gpu"


Stream_Ref :: struct {
	offset: u32,
	count:  u32,
}

Stream_Buffer :: struct {
	ptr:  gpu.ptr,
	used: i64,
}

Stream_Desc :: struct {
	data:               rawptr,
	size, count, align: i64,
}

Stream_Meta :: struct {
	size, alignment: i64,
}

make_desc :: proc(slice: []$T, alignment: i64 = 16) -> Stream_Desc {
	return Stream_Desc {
		data = raw_data(slice),
		size = size_of(T),
		count = i64(len(slice)),
		align = alignment,
	}
}


Vertex_Stream_Type :: enum {
	POS,
	COL,
	IDX,
	UV,
}
Vertex_Stream_Set :: bit_set[Vertex_Stream_Type;u32]

@(rodata)
vertex_stream_meta := [Vertex_Stream_Type]Stream_Meta {
	.POS = {12, 16},
	.COL = {16, 16},
	.IDX = {4, 4},
	.UV  = {8, 8},
}

Mesh :: [Vertex_Stream_Type]Stream_Ref
Mesh_Source :: [Vertex_Stream_Type]Stream_Desc
Vertex_Buffers :: [Vertex_Stream_Type]Stream_Buffer


Instance_Stream_Type :: enum {
	MODEL,
}

@(rodata)
instance_stream_meta := [Instance_Stream_Type]Stream_Meta {
	.MODEL = {64, 16},
}

Instance :: [Instance_Stream_Type]Stream_Ref
Instance_Source :: [Instance_Stream_Type]Stream_Desc
Instance_Buffers :: [Instance_Stream_Type]Stream_Buffer


Mesh_ID :: distinct u32

Mesh_Table :: struct {
	meshes:    [dynamic]Mesh,
	instances: [dynamic]Instance,
	sets:      map[Vertex_Stream_Set][dynamic]Mesh_ID,
}


upload_streams :: proc(
	streams: ^[$Enum]Stream_Buffer,
	arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	sources: [Enum]Stream_Desc,
	meta: [Enum]Stream_Meta,
	refs: ^[Enum]Stream_Ref,
) -> (
	set: bit_set[Enum;u32],
) {
	for s in Enum {
		if sources[s].count == 0 do continue
		set += {s}

		m := meta[s]
		d := sources[s]

		elem_size := d.size != 0 ? d.size : m.size
		alignment := d.align != 0 ? d.align : m.alignment
		bytes := d.count * elem_size

		stage := gpu.arena_alloc_raw(arena, bytes, alignment)
		mem.copy(stage.cpu, d.data, int(bytes))

		byte_offset := streams^[s].used
		refs^[s].offset = u32(byte_offset / elem_size)
		refs^[s].count = u32(d.count)

		gpu.cmd_mem_copy_raw(
			cmd,
			gpu.mem_suballoc(streams^[s].ptr, byte_offset, 1, bytes),
			stage,
			bytes,
		)

		streams^[s].used += bytes
	}

	return set
}


add_mesh :: proc(
	table: ^Mesh_Table,
	streams: ^Vertex_Buffers,
	arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	source: Mesh_Source,
) -> Mesh_ID {
	mesh: Mesh
	set := upload_streams(streams, arena, cmd, source, vertex_stream_meta, &mesh)

	id := Mesh_ID(u32(len(table.meshes)))
	append(&table.meshes, mesh)
	append(&table.instances, Instance{})

	if _, ok := table.sets[set]; !ok {
		table.sets[set] = {}
	}
	append(&table.sets[set], id)

	return id
}

add_instances :: proc(
	table: ^Mesh_Table,
	streams: ^Instance_Buffers,
	arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	mesh_id: Mesh_ID,
	source: Instance_Source,
) {
	idx := int(mesh_id)
	group := table.instances[idx]
	_ = upload_streams(streams, arena, cmd, source, instance_stream_meta, &group)
	table.instances[idx] = group
}

setup_scene :: proc(
) -> (
	vstreams: Vertex_Buffers,
	istreams: Instance_Buffers,
	table: Mesh_Table,
) {
	for &s in vstreams {
		s.ptr = gpu.mem_alloc_raw(1, 1024 * 1024, 16, gpu.Memory.GPU)
	}
	for &s in istreams {
		s.ptr = gpu.mem_alloc_raw(1, 1024 * 1024, 16, gpu.Memory.GPU)
	}

	upload := gpu.arena_create()
	defer gpu.arena_destroy(&upload)
	cmd := gpu.commands_begin(.Main)

	tri_pos := [][3]f32{{-0.5, -0.5, 0}, {0.5, -0.5, 0}, {0, 0.5, 0}}
	tri_col := [][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}
	tri_idx := []u32{0, 1, 2}
	tri_uv := [][2]f32{{0, 0}, {1, 0}, {0.5, 1}}

	source1: Mesh_Source
	source1[.POS] = make_desc(tri_pos)
	source1[.COL] = make_desc(tri_col)
	source1[.IDX] = make_desc(tri_idx)
	id1 := add_mesh(&table, &vstreams, &upload, cmd, source1)

	source2: Mesh_Source
	source2[.POS] = make_desc(tri_pos)
	source2[.UV] = make_desc(tri_uv)
	source2[.IDX] = make_desc(tri_idx)
	id2 := add_mesh(&table, &vstreams, &upload, cmd, source2)

	models1 := [][16]f32 {
		intrinsics.matrix_flatten(linalg.MATRIX4F32_IDENTITY),
		intrinsics.matrix_flatten(linalg.matrix4_translate_f32([3]f32{1.0, 0, 0})),
		intrinsics.matrix_flatten(linalg.matrix4_translate_f32([3]f32{-1.0, 0, 0})),
	}
	isource1: Instance_Source
	isource1[.MODEL] = make_desc(models1)
	add_instances(&table, &istreams, &upload, cmd, id1, isource1)

	models2 := [][16]f32{intrinsics.matrix_flatten(linalg.MATRIX4F32_IDENTITY)}
	isource2: Instance_Source
	isource2[.MODEL] = make_desc(models2)
	add_instances(&table, &istreams, &upload, cmd, id2, isource2)

	gpu.cmd_barrier(cmd, .Transfer, .All)
	gpu.queue_submit(.Main, {cmd})
	gpu.wait_idle()

	return vstreams, istreams, table
}


Global_Data :: struct #align (16) {
	vstreams:  [Vertex_Stream_Type]rawptr,
	istreams:  [Instance_Stream_Type]rawptr,
	view_proj: [16]f32,
}

Draw_Data :: struct #align (8) {
	set:            u32,
	instance_count: u32,
	voffsets:       [Vertex_Stream_Type]u32,
	ioffsets:       [Instance_Stream_Type]u32,
}

Indirect_Draw :: struct #align (16) {
	using cmd: gpu.Draw_Indexed_Indirect_Command,
	data:      Draw_Data,
}


render_scene_indirect :: proc(
	cmd: gpu.Command_Buffer,
	arena: ^gpu.Arena,
	vstreams: ^Vertex_Buffers,
	istreams: ^Instance_Buffers,
	table: ^Mesh_Table,
) {
	global := gpu.arena_alloc(arena, Global_Data)
	#unroll for s in Vertex_Stream_Type {
		global.cpu.vstreams[s] = vstreams^[s].ptr.gpu.ptr
	}
	#unroll for s in Instance_Stream_Type {
		global.cpu.istreams[s] = istreams^[s].ptr.gpu.ptr
	}
	global.cpu.view_proj = intrinsics.matrix_flatten(linalg.MATRIX4F32_IDENTITY)

	for set, mesh_ids in table.sets {
		draw_count := len(mesh_ids)
		if draw_count == 0 do continue
		if .IDX not_in set do continue

		indirects := make([]Indirect_Draw, draw_count, context.temp_allocator)

		for id, i in mesh_ids {
			mesh := table.meshes[int(id)]
			inst := table.instances[int(id)]

			indirects[i].cmd.index_count = mesh[.IDX].count
			indirects[i].cmd.instance_count = inst[.MODEL].count
			indirects[i].cmd.first_index = mesh[.IDX].offset
			indirects[i].cmd.vertex_offset = 0
			indirects[i].cmd.first_instance = inst[.MODEL].offset

			indirects[i].data.set = transmute(u32)(set)
			indirects[i].data.instance_count = inst[.MODEL].count

			for s in set {
				indirects[i].data.voffsets[s] = mesh[s].offset
			}
			for s in Instance_Stream_Type {
				indirects[i].data.ioffsets[s] = inst[s].offset
			}
		}

		indirect_bytes := size_of(Indirect_Draw) * draw_count
		indirect_alloc := gpu.arena_alloc_raw(arena, indirect_bytes, 16)
		mem.copy(indirect_alloc.cpu, raw_data(indirects), indirect_bytes)

		count_alloc := gpu.arena_alloc(arena, u32)
		count_alloc.cpu^ = u32(draw_count)

		gpu.cmd_draw_indexed_indirect_multi_raw(
			cmd,
			global,
			gpu.null,
			vstreams^[.IDX].ptr,
			.U32,
			indirect_alloc,
			size_of(Indirect_Draw),
			count_alloc,
		)
	}
}
