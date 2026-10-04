import "shared/shared.slang";

struct VertData {
  float3 *pos;
  float4 *col;
};

struct VSOut {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VSOut vertMain(uint vert_id: SV_VertexID,
               GraphicsPipelineData<VertData, void, void> data) {
  VSOut vert_out;
  vert_out.pos = float4(data.vert.pos[vert_id], 1.0);
  // vert_out.pos = data.vert.pos[vert_id];
  vert_out.color = data.vert.col[vert_id];
  return vert_out;
}

[shader("fragment")]
float4 fragMain(VSOut input) : SV_Target { return input.color; }
