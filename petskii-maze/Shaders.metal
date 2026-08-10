//
//  Shaders.metal
//  petskii-maze
//
//  Created by Vladimir Kosickij on 10.08.2026.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 viewportSize;    // drawable size, in pixels
    float2 origin;          // ox, oy — top-left of the grid, in pixels
    float cellSize;         // px per cell (== px * GLYPH)
    uint cols;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexShader(uint vertexID             [[vertex_id]],
                              uint instanceID           [[instance_id]],
                              constant Uniforms &u      [[buffer(0)]],
                              device const uchar *grid  [[buffer(1)]])
{
    // Quad corners from vertex_id, no vertex buffer needed:
    // 0:(0,0) 1:(1,0) 2:(0,1) 3:(1,1) — valid triangle-strip winding for a quad.
    float2 corner = float2(vertexID & 1, vertexID >> 1);

    uint col = instanceID % u.cols;
    uint row = instanceID / u.cols;

    float2 cellOrigin = u.origin + float2(col, row) * u.cellSize;
    float2 pixelPos = cellOrigin + corner * u.cellSize;

    float2 ndc;
    ndc.x = (pixelPos.x / u.viewportSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pixelPos.y / u.viewportSize.y) * 2.0; // pixel Y-down -> NDC Y-up

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);

    // grid[instanceID] is 0=slash, 1=backslash, 2=blank -> atlas has 3 horizontal slices
    uchar glyph = grid[instanceID];
    out.uv = float2((float(glyph) + corner.x) / 3.0, corner.y);
    return out;
}

fragment float4 fragmentShader(VertexOut in             [[stage_in]],
                               texture2d<float> atlas   [[texture(0)]],
                               sampler samp             [[sampler(0)]])
{
    return atlas.sample(samp, in.uv);
}
