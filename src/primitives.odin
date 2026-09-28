package main

import "base:intrinsics"
import "core:math/linalg"
import "core:mem"
import "gpu/gpu"


Vertex_Stream_Type :: enum {
	POS,
	COL,
	IDX,
	UV,
}

Vertex_Stream_Set :: bit_set[Vertex_Stream_Type;u32]

@(rodata)
vertex_stream_meta := [Vertex_Stream_Type]struct {
	size, alignment: i64,
} {
	.POS = {12, 16},
	.COL = {16, 16},
	.IDX = {4, 4},
	.UV  = {8, 8},
}

Vertex_Stream :: struct {
	offset: u32,
	count:  u32,
}

Mesh :: distinct [Vertex_Stream_Type]Vertex_Stream

Vertex_Streams :: distinct [Vertex_Stream_Type]struct {
	ptr:  gpu.ptr,
	used: i64,
}

Mesh_Source :: distinct [Vertex_Stream_Type]Stream_Desc


Instance_Stream_Type :: enum {
	MODEL,
}

Instance_Stream_Set :: bit_set[Instance_Stream_Type;u32]

@(rodata)
instance_stream_meta := [Instance_Stream_Type]struct {
	size, alignment: i64,
} {
	.MODEL = {64, 16},
}

Instance_Stream :: struct {
	offset: u32,
	count:  u32,
}

Instance_Group :: distinct [Instance_Stream_Type]Instance_Stream

Instance_Streams :: distinct [Instance_Stream_Type]struct {
	ptr:  gpu.ptr,
	used: i64,
}

Instance_Source :: distinct [Instance_Stream_Type]Stream_Desc


Mesh_ID :: distinct u32
Instance_ID :: distinct u32

Stream_Desc :: struct {
	data:               rawptr,
	size, count, align: i64,
}

make_desc :: proc(slice: []$T, alignment: i64 = 0) -> Stream_Desc {
	return Stream_Desc {
		data = raw_data(slice),
		size = size_of(T),
		count = i64(len(slice)),
		align = alignment,
	}
}


Mesh_Table :: struct {
	meshes:    [dynamic]Mesh,
	instances: [dynamic]Instance_Group,
	sets:      map[Vertex_Stream_Set][dynamic]Mesh_ID,
}


add_mesh :: proc(
	table: ^Mesh_Table,
	streams: ^Vertex_Streams,
	arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	source: Mesh_Source,
) -> Mesh_ID {
	mesh: Mesh

	set: Vertex_Stream_Set
	#unroll for s in Vertex_Stream_Type {
		if source[s].count > 0 {
			set += {s}

			meta := vertex_stream_meta[s]
			desc := source[s]

			elem_size := desc.size != 0 ? desc.size : meta.size
			alignment := desc.align != 0 ? desc.align : meta.alignment
			count := desc.count
			bytes := count * elem_size

			stage := gpu.arena_alloc_raw(arena, bytes, alignment)
			mem.copy(stage.cpu, desc.data, int(bytes))

			byte_offset := streams^[s].used
			mesh[s].offset = u32(byte_offset / elem_size)
			mesh[s].count = u32(count)

			gpu.cmd_mem_copy_raw(
				cmd,
				gpu.mem_suballoc(streams^[s].ptr, byte_offset, 1, bytes),
				stage,
				bytes,
			)

			streams^[s].used += bytes
		}
	}

	id := Mesh_ID(u32(len(table.meshes)))
	append(&table.meshes, mesh)

	append(&table.instances, Instance_Group{})

	if _, ok := table.sets[set]; !ok {
		table.sets[set] = {}
	}
	append(&table.sets[set], id)

	return id
}


add_instances :: proc(
	table: ^Mesh_Table,
	streams: ^Instance_Streams,
	arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	mesh_id: Mesh_ID,
	source: Instance_Source,
) {
	group := table.instances[mesh_id]

	#unroll for s in Instance_Stream_Type {
		if source[s].count > 0 {
			meta := instance_stream_meta[s]
			desc := source[s]

			elem_size := desc.size != 0 ? desc.size : meta.size
			alignment := desc.align != 0 ? desc.align : meta.alignment
			count := desc.count
			bytes := count * elem_size

			stage := gpu.arena_alloc_raw(arena, bytes, alignment)
			mem.copy(stage.cpu, desc.data, int(bytes))

			byte_offset := streams^[s].used
			group[s].offset = u32(byte_offset / elem_size)
			group[s].count = u32(count)

			gpu.cmd_mem_copy_raw(
				cmd,
				gpu.mem_suballoc(streams^[s].ptr, byte_offset, 1, bytes),
				stage,
				bytes,
			)

			streams^[s].used += bytes
		}
	}

	table.instances[mesh_id] = group
}


setup_scene :: proc(
) -> (
	vstreams: Vertex_Streams,
	istreams: Instance_Streams,
	table: Mesh_Table,
) {

	for &stream in vstreams {
		stream.ptr = gpu.mem_alloc_raw(1, 1024 * 1024, 16, gpu.Memory.GPU)
	}
	for &stream in istreams {
		stream.ptr = gpu.mem_alloc_raw(1, 1024 * 1024, 16, gpu.Memory.GPU)
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
	vstreams: ^Vertex_Streams,
	istreams: ^Instance_Streams,
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
			mesh := table.meshes[id]
			inst := table.instances[id]

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
