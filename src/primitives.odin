package main

import "core:mem"
import "gpu/gpu"

Pos :: distinct [3]f32
Col :: distinct [4]f32
Index :: distinct u32

example :: proc(
	upload: ^gpu.Arena,
) -> (
	pos_stream: gpu.ptr_t(Pos),
	col_stream: gpu.ptr_t(Col),
	idx_stream: gpu.ptr_t(Index),
) {

	pos_stream = gpu.mem_alloc(Pos, gpu.Memory.GPU)
	col_stream = gpu.mem_alloc(Col, gpu.Memory.GPU)
	idx_stream = gpu.mem_alloc(Index, gpu.Memory.GPU)

	tri_pos := gpu.arena_alloc(upload, Pos)
	mem.copy(tri_pos.cpu, raw_data([]Pos{{-1, -1, 0}, {0, 1, 0}, {1, -1, 0}}), 3)
	tri_col := gpu.arena_alloc(upload, Col)
	mem.copy(tri_col.cpu, raw_data([]Col{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}), 3)
	tri_idx := gpu.arena_alloc(upload, Index)
	mem.copy(tri_idx.cpu, raw_data([]Index{0, 1, 2}), 3)

	cmd := gpu.commands_begin(.Main)

	gpu.cmd_mem_copy(cmd, pos_stream, tri_pos)
	gpu.cmd_mem_copy(cmd, col_stream, tri_col)
	gpu.cmd_mem_copy(cmd, idx_stream, tri_idx)

	gpu.cmd_barrier(cmd, .Transfer, .All)
	gpu.queue_submit(.Main, {cmd})


	return
}

