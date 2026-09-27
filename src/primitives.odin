package main

import "../src/gpu/gpu"
import "core:mem"

Stream_Type :: enum {
	POS,
	IDX,
	UV,
	COLOR,
	NORMAL,
	TANGENT,
}

Stream_Set :: bit_set[Stream_Type;u32]

Stream_Desc :: struct {
	elem_size: i64,
	alignment: i64,
}

@(rodata)
stream_descs := [Stream_Type]Stream_Desc {
	.POS     = {12, 16},
	.IDX     = {4, 4},
	.UV      = {8, 8},
	.COLOR   = {16, 16},
	.NORMAL  = {12, 16},
	.TANGENT = {16, 16},
}

Source :: struct {
	data:  rawptr,
	count: i64,
}

// FIXED: Polymorphic inference
make_source :: proc(slice: []$T) -> Source {
	return Source{raw_data(slice), i64(len(slice))}
}

Buffers :: struct {
	streams:  [Stream_Type]gpu.ptr,
	used:     [Stream_Type]i64,
	capacity: int,
	meshes:   [dynamic]Mesh,
}

Mesh :: struct {
	offsets: [Stream_Type]u32,
	counts:  [Stream_Type]u32,
	set:     Stream_Set,
}

buffers_init :: proc(b: ^Buffers, capacity_bytes: int) {
	b.capacity = capacity_bytes
	for s in Stream_Type {
		desc := stream_descs[s]
		b.streams[s] = gpu.mem_alloc_raw(1, capacity_bytes, desc.alignment, .GPU)
	}
}

upload_mesh :: proc(
	b: ^Buffers,
	arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	sources: [Stream_Type]Source,
	set: Stream_Set,
) -> Mesh {
	mesh: Mesh
	mesh.set = set

	for s in set {
		desc := stream_descs[s]
		src := sources[s]
		bytes := src.count * desc.elem_size

		stage := gpu.arena_alloc_raw(arena, bytes, desc.alignment)
		mem.copy(stage.cpu, src.data, int(bytes))

		byte_offset := b.used[s]
		mesh.offsets[s] = u32(byte_offset / desc.elem_size)
		mesh.counts[s] = u32(src.count)

		gpu.cmd_mem_copy_raw(
			cmd,
			gpu.mem_suballoc(b.streams[s], byte_offset, 1, bytes),
			stage,
			bytes,
		)

		b.used[s] += bytes
	}

	return mesh
}
