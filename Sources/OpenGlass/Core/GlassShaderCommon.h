#ifndef GlassShaderCommon_h
#define GlassShaderCommon_h

#include <metal_stdlib>
using namespace metal;

struct GlassVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

inline float sdRoundedBox(float2 p, float2 b, float4 radii) {
    float2 r = (p.x > 0.0) ? radii.yw : radii.xz;
    float radius = (p.y > 0.0) ? r.y : r.x;

    float2 q = abs(p) - b + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

inline float getCornerRadius(float2 p, float4 radii) {
    float2 r = (p.x > 0.0) ? radii.yw : radii.xz;
    return (p.y > 0.0) ? r.y : r.x;
}

inline float3 applyTintBlend(float3 base, float3 tint, float mode, float intensity) {
    float3 result;

    if (mode < 0.5) {
        result = base * tint;
    } else if (mode < 1.5) {
        float3 low = 2.0 * base * tint;
        float3 high = 1.0 - 2.0 * (1.0 - base) * (1.0 - tint);
        result = mix(low, high, step(0.5, base));
    } else if (mode < 2.5) {
        result = 1.0 - (1.0 - base) * (1.0 - tint);
    } else if (mode < 3.5) {
        result = base / max(1.0 - tint, 0.001);
        result = min(result, float3(1.0));
    } else {
        result = (1.0 - 2.0 * tint) * base * base + 2.0 * tint * base;
    }

    return mix(base, result, intensity);
}

constant float kGoldenAngle = 2.39996323;
constant int kBlurSamples = 32;

inline float sampleBlurredChannel(
    texture2d<float, access::sample> tex,
    sampler s,
    float2 uv,
    float2 texelSize,
    float radius,
    int channel
) {
    if (radius < 0.5) {
        return tex.sample(s, uv)[channel];
    }

    float value = tex.sample(s, uv)[channel];
    float totalWeight = 1.0;

    for (int i = 1; i < kBlurSamples; i++) {
        float t = float(i) / float(kBlurSamples - 1);
        float r = sqrt(t) * radius;
        float theta = float(i) * kGoldenAngle;

        float2 offset = float2(cos(theta), sin(theta)) * r * texelSize;
        float2 sampleUV = clamp(uv + offset, float2(0.001), float2(0.999));

        float weight = 1.0 - t * 0.7;
        value += tex.sample(s, sampleUV)[channel] * weight;
        totalWeight += weight;
    }

    return value / totalWeight;
}

inline GlassVertexOut glassVertexShader(uint vertexID) {
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

    GlassVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

#endif
