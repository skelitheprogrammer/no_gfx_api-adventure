import "shared/shared.slang";

#define STREAM_POS 0
#define STREAM_IDX 1
#define STREAM_UV 2
#define STREAM_COLOR 3
#define STREAM_NORMAL 4
#define STREAM_TANGENT 5
#define STREAM_COUNT 6

struct GlobalData {
  uint8_t *streams[STREAM_COUNT];
  float4x4 view_proj;
};

struct DrawData {
  uint set;
  uint offsets[STREAM_COUNT];
};

struct VertexOutput {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VertexOutput vertMain(uint vertex_index: SV_VertexID,
                        GraphicsPipelineData<DrawData, GlobalData, void> data) {
  DrawData *draw = data.vert;
  GlobalData *global = data.frag;
  VertexOutput out;

  uint idx = vertex_index;

  float3 *pos_buffer = (float3 *)global->streams[STREAM_POS];
  float3 pos = pos_buffer[draw->offsets[STREAM_POS] + idx];
  out.pos = mul(global->view_proj, float4(pos, 1.0));

  if ((draw->set & (1u << STREAM_COLOR)) != 0u) {
    float4 *col_buffer = (float4 *)global->streams[STREAM_COLOR];
    out.color = col_buffer[draw->offsets[STREAM_COLOR] + idx];
  } else {
    out.color = float4(1, 1, 1, 1);
  }

  return out;
}

[shader("fragment")]
float4 fragMain(VertexOutput input) : SV_Target { return input.color; }
