package main

import "core:reflect"
import "gpu/gpu"

Buffer_Type :: enum {
	POS,
	COL,
	IDX,
	MDI,
	CNT,
}

Buffer_Type_Set :: bit_set[Buffer_Type]

@(rodata)
buffer_ids := [Buffer_Type]typeid {
	.POS = [3]f32,
	.COL = [4]f32,
	.IDX = u32,
	.MDI = gpu.Draw_Indexed_Indirect_Command,
	.CNT = u32,
}

buffer_size :: #force_inline proc(type: Buffer_Type) -> int {
	return reflect.size_of_typeid(buffer_ids[type])
}

commit_upload :: proc(ptrs: [Buffer_Type]gpu.ptr, buffers: [Buffer_Type]gpu.ptr) {
	cmd := gpu.commands_begin(.Main)

	for ptr, t in ptrs {
		if ptr == gpu.null do continue
		gpu.cmd_mem_copy_raw(cmd, buffers[t], ptr, 0)
	}

	gpu.cmd_barrier(cmd, .Transfer, .All)
	gpu.queue_submit(.Main, {cmd})

}

