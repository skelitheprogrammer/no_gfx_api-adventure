package main

import "gpu/gpu"

gpuptr_bytes :: #force_inline proc "contextless" (ptr: gpu.gpuptr) -> i64 {
	impl := transmute(gpu.Alloc_Impl_Info)ptr._impl
	return i64(uintptr(impl.range_end) - uintptr(ptr.ptr))
}

