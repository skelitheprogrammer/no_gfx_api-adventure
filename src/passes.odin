package main

import "../src/gpu/gpu"
import "base:intrinsics"
import "core:math/linalg"

Global_Data :: struct #align (16) {
	streams:   [Stream_Type]rawptr,
	view_proj: [16]f32,
}

Draw_Data :: struct #align (8) {
	set:     u32,
	offsets: [Stream_Type]u32,
}

opaque_pass :: proc(
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	b: ^Buffers,
	shaders: Shader_Pair,
) {
	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])
	gpu.cmd_set_raster_state(cmd, {.Triangle_List, .None, false})
	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = target, clear_color = {0.7, 0.7, 0.7, 1.0}}}},
	)

	global := gpu.arena_alloc(arena, Global_Data)
	for s in Stream_Type {
		global.cpu.streams[s] = b.streams[s].gpu.ptr
	}
	global.cpu.view_proj = intrinsics.matrix_flatten(linalg.MATRIX4F32_IDENTITY)

	for m in b.meshes {
		draw := gpu.arena_alloc(arena, Draw_Data)
		draw.cpu.set = transmute(u32)(m.set)
		for s in m.set {
			draw.cpu.offsets[s] = m.offsets[s]
		}

		idx_offset_bytes := i64(m.offsets[.IDX]) * stream_descs[.IDX].elem_size
		idx_count := m.counts[.IDX]

		gpu.cmd_draw_indexed_raw(
			cmd,
			draw,
			global,
			gpu.mem_suballoc(
				b.streams[.IDX],
				idx_offset_bytes,
				stream_descs[.IDX].elem_size,
				i64(idx_count),
			),
			.U32,
			idx_count,
		)
	}

	gpu.cmd_end_render_pass(cmd)
}
