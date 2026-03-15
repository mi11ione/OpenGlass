#include <metal_stdlib>
using namespace metal;

struct CompositorVertexIn {
    packed_float2 position;
    packed_float2 texCoord;
    float opacity;
    packed_float4 bgColor;
    float hasTexture;
};

struct CompositorVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float  opacity;
    float4 bgColor;
    float  hasTexture;
};

vertex CompositorVertexOut compositorVertexShader(
    uint vid [[vertex_id]],
    const device CompositorVertexIn *vertices [[buffer(0)]],
    constant float4 &viewport [[buffer(1)]]
) {
    float2 worldPos = float2(vertices[vid].position);
    float2 ndc;
    ndc.x = (worldPos.x - viewport.x) * viewport.z * 2.0 - 1.0;
    ndc.y = 1.0 - (worldPos.y - viewport.y) * viewport.w * 2.0;

    CompositorVertexOut out;
    out.position   = float4(ndc, 0.0, 1.0);
    out.texCoord   = float2(vertices[vid].texCoord);
    out.opacity    = vertices[vid].opacity;
    out.bgColor    = float4(vertices[vid].bgColor);
    out.hasTexture = vertices[vid].hasTexture;
    return out;
}

fragment float4 compositorFragmentShader(
    CompositorVertexOut in [[stage_in]],
    texture2d<float, access::sample> tex [[texture(0)]]
) {
    constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);

    float4 color = in.bgColor;

    if (in.hasTexture > 0.5) {
        float4 texColor = tex.sample(samp, in.texCoord);
        color = texColor + color * (1.0 - texColor.a);
    }

    color *= in.opacity;
    return color;
}

struct MaskBlitUniforms {
    float2 viewportSize;
    float2 captureOrigin;
    float invScale;
    float _pad;
    float2 maskBoundsOrigin;
    float2 maskBoundsInvSize;
    float2 imCol0;
    float2 imCol1;
    float2 imTranslation;
    float2 contentTexScale;
};

struct MaskBlitOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex MaskBlitOut maskBlitVertexShader(uint vid [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    MaskBlitOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

fragment float4 maskBlitFragmentShader(
    MaskBlitOut in [[stage_in]],
    texture2d<float, access::sample> contentTex [[texture(0)]],
    texture2d<float, access::sample> maskTex    [[texture(1)]],
    constant MaskBlitUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 contentUV = in.texCoord * uniforms.contentTexScale;
    float4 content = contentTex.sample(samp, contentUV);

    float2 worldPos = uniforms.captureOrigin + in.position.xy * uniforms.invScale;
    float2 maskLocal;
    maskLocal.x = worldPos.x * uniforms.imCol0.x + worldPos.y * uniforms.imCol1.x + uniforms.imTranslation.x;
    maskLocal.y = worldPos.x * uniforms.imCol0.y + worldPos.y * uniforms.imCol1.y + uniforms.imTranslation.y;
    float2 maskUV = (maskLocal - uniforms.maskBoundsOrigin) * uniforms.maskBoundsInvSize;

    float maskAlpha = 0.0;
    if (maskUV.x >= 0.0 && maskUV.x <= 1.0 && maskUV.y >= 0.0 && maskUV.y <= 1.0) {
        maskAlpha = maskTex.sample(samp, maskUV).a;
    }

    return content * maskAlpha;
}
