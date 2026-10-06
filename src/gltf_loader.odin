package main

import "base:runtime"
import "gpu/gpu"
import "vendor:cgltf"

User_Data :: struct {
	ctx:   runtime.Context,
	arena: ^gpu.Arena,
}

cgltf_alloc_proc :: proc "c" (user: rawptr, size: uint) -> rawptr {
	data := cast(^User_Data)user
	context = data.ctx
	return gpu.arena_alloc_raw(data.arena, size, 64).cpu
}

cgltf_free_proc :: proc "c" (user, ptr: rawptr) {}

@(rodata)
type_map := #partial [cgltf.attribute_type]Buffer_Type {
	.position = .POS,
	.color    = .COL,
}

load_gltf :: proc(
	path: cstring,
	arena: ^gpu.Arena,
) -> (
	ptrs: [Buffer_Type]gpu.ptr,
	res: cgltf.result,
) {

	opts := cgltf.options {
		memory = {
			alloc_func = cgltf_alloc_proc,
			free_func = cgltf_free_proc,
			user_data = rawptr(&User_Data{context, arena}),
		},
	}

	data := cgltf.parse_file(opts, path) or_return
	defer cgltf.free(data)

	cgltf.load_buffers(opts, data, path) or_return

	for mesh in data.meshes do for prim in mesh.primitives {
		accessors: [Buffer_Type]^cgltf.accessor

		for attr in prim.attributes {
			if attr.data == nil do continue
			accessors[type_map[attr.type]] = attr.data
		}

		if accessors[.POS] == nil do continue

		v_count := accessors[.POS].count
		if v_count == 0 do continue

		#unroll for t in Buffer_Type do if accessors[t] != nil {
			if t != .IDX || t != .MDI || t != .CNT {
				sz := buffer_size(t)
				float_count := uint(v_count) * uint(sz) / uint(size_of(f32))

				ptrs[t] = gpu.arena_alloc_raw(arena, sz, int(v_count), 64)
				_ = cgltf.accessor_unpack_floats(accessors[t], cast([^]f32)ptrs[t].cpu, float_count)
			}
		}

	}

	res = .success
	return
}

