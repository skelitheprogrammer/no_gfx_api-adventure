package main

import "../src/gpu/gpu"

opaque_pass :: proc(
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	shaders: Shader_Pair,
	pos: gpu.ptr_t(Pos),
	col: gpu.ptr_t(Col),
	idx: gpu.ptr_t(Index),
) {
	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = target, clear_color = {0.7, 0.7, 0.7, 1.0}}}},
	)
	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])
	gpu.cmd_set_raster_state(cmd, {.Triangle_List, .None, false})

	Vert_Data :: struct #all_or_none {
		pos, col: rawptr,
	}

	vert := gpu.arena_alloc(arena, Vert_Data)
	vert.cpu^ = {pos.gpu.ptr, col.gpu.ptr}

	gpu.cmd_draw(cmd, vert, gpu.null, 3)

	gpu.cmd_end_render_pass(cmd)
}

