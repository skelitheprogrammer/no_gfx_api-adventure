package main

import "gpu/gpu"

Buffer_Type :: enum {
	POS,
	COL,
	IDX,
	MDI,
	CNT,
}

buffer_ids :: [Buffer_Type]typeid {
	.POS = [3]f32,
	.COL = [4]f32,
	.IDX = u32,
	.MDI = gpu.Draw_Indexed_Indirect_Command,
	.CNT = u32,
}

