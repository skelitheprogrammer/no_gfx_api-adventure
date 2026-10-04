package main

import "../src/gpu/gpu"
import "base:runtime"
import "core:c"
import "core:flags"
import log "core:log"
import "core:os"
import sdl "vendor:sdl3"

Config :: struct {
	name:     cstring,
	capacity: i64,
	width:    c.int,
	height:   c.int,
}

default_config := Config{"TheGame", 1024, 3440, 1440}


main :: proc() {
	flags.parse_or_exit(&default_config, os.args)

	console_logger := log.create_console_logger(); defer log.destroy_console_logger(console_logger)
	context.logger = console_logger

	ensure(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := init_window(); defer sdl.DestroyWindow(window)

	scale := sdl.GetWindowDisplayScale(window)
	win := [2]i32{i32(f32(default_config.width) * scale), i32(f32(default_config.height) * scale)}

	ensure(gpu.init()); defer gpu.cleanup()
	gpu.swapchain_create_from_sdl(window, FLIGHT)

	renderer: Renderer
	renderer_init(&renderer, cast([2]u32)(win)); defer renderer_destroy(&renderer)

	opaque_pass_shaders := Shader_Pair {
		.Vertex   = gpu.shader_create(#load("../samples/triangle/unlit.vert.spv", []u32), .Vertex),
		.Fragment = gpu.shader_create(
			#load("../samples/triangle/unlit.frag.spv", []u32),
			.Fragment,
		),
	}; defer for &s in opaque_pass_shaders do gpu.shader_destroy(s)

	upload := gpu.arena_create(); defer gpu.arena_destroy(&upload)


	buffers := [Buffer_Type]gpu.ptr {
		.POS = gpu.mem_alloc_raw(
			size_of(buffer_ids[.POS]),
			default_config.capacity,
			16,
			gpu.Memory.GPU,
		),
		.COL = gpu.mem_alloc_raw(
			size_of(buffer_ids[.COL]),
			default_config.capacity,
			16,
			gpu.Memory.GPU,
		),
		.IDX = gpu.mem_alloc_raw(
			size_of(buffer_ids[.IDX]),
			default_config.capacity,
			16,
			gpu.Memory.GPU,
		),
		.MDI = gpu.mem_alloc_raw(
			size_of(buffer_ids[.MDI]),
			default_config.capacity,
			16,
			gpu.Memory.GPU,
		),
		.CNT = gpu.mem_alloc_raw(size_of(buffer_ids[.CNT]), 1, 16, gpu.Memory.GPU),
	}; defer for buffer in buffers do gpu.mem_free_raw(buffer)


	ts_freq := sdl.GetPerformanceFrequency()
	last_ts := sdl.GetPerformanceCounter()

	for handle_window_events() {
		sdl.GetWindowSizeInPixels(window, &win.x, &win.y)
		if .MINIMIZED in sdl.GetWindowFlags(window) || win.x <= 0 || win.y <= 0 {
			sdl.Delay(16)
			continue
		}

		now_ts := sdl.GetPerformanceCounter()
		last_ts = now_ts

		cmd, swapchain, arena := frame_begin(&renderer, win) or_break

		opaque_pass(cmd, swapchain, arena, opaque_pass_shaders, buffers)

		frame_end(&renderer, cmd)

	}

	gpu.wait_idle()
}

init_window :: proc() -> (window: ^sdl.Window) {
	window = sdl.CreateWindow(
		default_config.name,
		default_config.width,
		default_config.height,
		{.VULKAN, .HIGH_PIXEL_DENSITY, .BORDERLESS, .RESIZABLE},
	)
	ensure(window != nil)

	return
}


handle_window_events :: proc() -> bool {
	evt: sdl.Event
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			return false
		case .WINDOW_CLOSE_REQUESTED:
			sdl.Quit(); return false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 do return false
		}
	}
	return true
}

