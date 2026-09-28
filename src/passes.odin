package main

import "../src/gpu/gpu"
import "base:intrinsics"
import "core:math/linalg"

opaque_pass :: proc(
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	shaders: Shader_Pair,
) {
	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])
	gpu.cmd_set_raster_state(cmd, {.Triangle_List, .None, false})
	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = target, clear_color = {0.7, 0.7, 0.7, 1.0}}}},
	)


	gpu.cmd_end_render_pass(cmd)
}
