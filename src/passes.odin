package main

import "../src/gpu/gpu"

opaque_pass :: proc(
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	shaders: Shader_Pair,
	buffers: [Buffer_Type]gpu.ptr,
) {
	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = target, clear_color = {0.1, 0.1, 0.1, 1.0}}}},
	)
	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])
	gpu.cmd_set_raster_state(cmd, {.Triangle_List, .None, false})

	Vert_Data :: struct #all_or_none {
		pos, col: rawptr,
	}

	vert := gpu.arena_alloc(arena, Vert_Data)
	vert.cpu^ = {buffers[.POS].gpu.ptr, buffers[.COL].gpu.ptr}

	gpu.cmd_draw_indexed_indirect_multi_raw(
		cmd,
		vert,
		gpu.null,
		buffers[.IDX].gpu,
		.U32,
		buffers[.MDI].gpu,
		size_of(gpu.Draw_Indexed_Indirect_Command),
		buffers[.CNT].gpu,
	)

	gpu.cmd_end_render_pass(cmd)
}

