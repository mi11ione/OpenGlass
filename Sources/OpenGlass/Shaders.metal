#include <metal_stdlib>
using namespace metal;

struct GlassVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

inline float sdRoundedBox(float2 p, float2 b, float radius) {
    float2 q = abs(p) - b + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
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

inline float3 sampleBlurredAll(
    texture2d<float, access::sample> tex,
    sampler s,
    float2 uv,
    float2 texelSize,
    float radius
) {
    if (radius < 0.5) {
        return tex.sample(s, uv).rgb;
    }

    float3 value = tex.sample(s, uv).rgb;
    float totalWeight = 1.0;

    for (int i = 1; i < kBlurSamples; i++) {
        float t = float(i) / float(kBlurSamples - 1);
        float r = sqrt(t) * radius;
        float theta = float(i) * kGoldenAngle;

        float2 offset = float2(cos(theta), sin(theta)) * r * texelSize;
        float2 sampleUV = clamp(uv + offset, float2(0.001), float2(0.999));

        float weight = 1.0 - t * 0.7;
        value += tex.sample(s, sampleUV).rgb * weight;
        totalWeight += weight;
    }

    return value / totalWeight;
}

struct Uniforms {
    float2 size;
    float2 renderSize;
    float2 offset;
    float2 backgroundSize;
    float padding;
    float cornerRadius;
    float blurRadius;
    float refractionStrength;
    float chromeStrength;
    float edgeBandMultiplier;
    float zoom;
    float edgeShadowStrength;
    float overallShadowStrength;
    float glassTintStrength;
    float isDarkMode;
    float physScale;
    float physOpacity;
    float physStretchX;
    float physStretchY;
    float physRotation;
    float physOffsetX;
    float physOffsetY;
    float hasContent;
    float tintRegime;
};

struct LumUniforms {
    float2 offset;
    float2 size;
    float2 backgroundSize;
};

kernel void averageLuminance(
    texture2d<float, access::sample> backgroundTexture [[texture(0)]],
    constant LumUniforms &uniforms [[buffer(0)]],
    device float *avgLumOut [[buffer(1)]],
    uint tid [[thread_position_in_grid]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float avgLum = 0.0;
    for (int sy = 0; sy < 3; sy++) {
        for (int sx = 0; sx < 3; sx++) {
            float2 sp = uniforms.offset + uniforms.size *
                float2((float(sx) + 0.5) / 3.0, (float(sy) + 0.5) / 3.0);
            float2 suv = clamp(sp / uniforms.backgroundSize, float2(0.001), float2(0.999));
            avgLum += dot(backgroundTexture.sample(s, suv, level(0)).rgb,
                          float3(0.299, 0.587, 0.114));
        }
    }
    *avgLumOut = avgLum / 9.0;
}

vertex GlassVertexOut vertexShader(uint vertexID [[vertex_id]]) {
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

fragment float4 fragmentShader(
    GlassVertexOut in [[stage_in]],
    texture2d<float, access::sample> backgroundTexture [[texture(0)]],
    texture2d<float, access::sample> contentTexture [[texture(1)]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 renderPixelPos = in.texCoord * uniforms.renderSize;
    float2 pixelPos = renderPixelPos - float2(uniforms.padding);
    float2 center = uniforms.size * 0.5;
    float2 offsetPos = pixelPos - float2(uniforms.physOffsetX, uniforms.physOffsetY);
    float2 fromCenter = offsetPos - center;

    float cosR = cos(uniforms.physRotation);
    float sinR = sin(uniforms.physRotation);
    float2 rotated = float2(
        fromCenter.x * cosR - fromCenter.y * sinR,
        fromCenter.x * sinR + fromCenter.y * cosR
    );

    float2 stretched = rotated / float2(uniforms.physStretchX, uniforms.physStretchY);

    float pScale = uniforms.physScale;
    float halfWidth = uniforms.size.x * 0.5 * pScale;
    float halfHeight = uniforms.size.y * 0.5 * pScale;
    float2 halfSize = float2(halfWidth, halfHeight);
    float scaledCornerRadius = uniforms.cornerRadius * pScale;

    float sdf = sdRoundedBox(stretched, halfSize, scaledCornerRadius);
    float edgeAA = length(float2(dfdx(sdf), dfdy(sdf)));
    edgeAA = max(edgeAA, 0.5);

    if (sdf > edgeAA * 2.0) {
        discard_fragment();
    }

    float distFromEdge = -sdf;
    float effectiveSize = min(uniforms.size.x * uniforms.physStretchX,
                              uniforms.size.y * uniforms.physStretchY);
    float edgeBand = effectiveSize * pScale * uniforms.edgeBandMultiplier;

    float edgeFactor = 1.0 - smoothstep(0.0, edgeBand, distFromEdge);
    edgeFactor = edgeFactor * edgeFactor * edgeFactor * 2.0;

    float visualHalfWidth = halfWidth * uniforms.physStretchX;
    float visualHalfHeight = halfHeight * uniforms.physStretchY;

    float insetX = min(scaledCornerRadius, halfWidth);
    float insetY = min(scaledCornerRadius, halfHeight);
    float minX = center.x - halfWidth + insetX;
    float maxX = center.x + halfWidth - insetX;
    float minY = center.y - halfHeight + insetY;
    float maxY = center.y + halfHeight - insetY;
    float2 nearestCenterPoint = float2(
        clamp(offsetPos.x, minX, maxX),
        clamp(offsetPos.y, minY, maxY)
    );

    float2 toCenter = nearestCenterPoint - offsetPos;
    float distToCenter = length(toCenter);
    toCenter = distToCenter > 0.001 ? toCenter / distToCenter : float2(0.0);

    float2 normFromCenter = fromCenter / float2(visualHalfWidth, visualHalfHeight);
    float distNorm = length(normFromCenter);
    float zoomFactor = max(0.0, 1.0 - distNorm * distNorm);
    float zoomStrength = uniforms.zoom - 1.0;
    float2 magOffset = -normFromCenter * zoomFactor * zoomStrength * min(visualHalfWidth, visualHalfHeight);

    float disp = edgeFactor * uniforms.refractionStrength * edgeBand;
    float chrome = edgeFactor * uniforms.chromeStrength;

    float2 greenOff = toCenter * disp + magOffset;
    float2 texelSize = 1.0 / uniforms.backgroundSize;
    float blurAmount = uniforms.blurRadius;

    float3 color;
    if (chrome < 0.001) {
        float2 uv = (uniforms.offset + pixelPos + greenOff) / uniforms.backgroundSize;
        uv = clamp(uv, float2(0.001), float2(0.999));
        color = sampleBlurredAll(backgroundTexture, texSampler, uv, texelSize, blurAmount);
    } else {
        float2 redOff = toCenter * (disp + chrome) + magOffset;
        float2 blueOff = toCenter * (disp - chrome) + magOffset;

        float2 redUV = (uniforms.offset + pixelPos + redOff) / uniforms.backgroundSize;
        float2 greenUV = (uniforms.offset + pixelPos + greenOff) / uniforms.backgroundSize;
        float2 blueUV = (uniforms.offset + pixelPos + blueOff) / uniforms.backgroundSize;

        redUV = clamp(redUV, float2(0.001), float2(0.999));
        greenUV = clamp(greenUV, float2(0.001), float2(0.999));
        blueUV = clamp(blueUV, float2(0.001), float2(0.999));

        float r = sampleBlurredChannel(backgroundTexture, texSampler, redUV, texelSize, blurAmount, 0);
        float g = sampleBlurredChannel(backgroundTexture, texSampler, greenUV, texelSize, blurAmount, 1);
        float b = sampleBlurredChannel(backgroundTexture, texSampler, blueUV, texelSize, blurAmount, 2);
        color = float3(r, g, b);
    }

    bool dark = uniforms.isDarkMode > 0.5;
    float regime = uniforms.tintRegime;

    float lum = dot(color, float3(0.299, 0.587, 0.114));
    float tintAmount;
    if (dark) {
        tintAmount = (1.0 - lum) * uniforms.glassTintStrength * 1.15;
        color = mix(color, float3(0.10), tintAmount);
    } else {
        tintAmount = max(lum, 0.08) * uniforms.glassTintStrength * mix(1.0, 0.35, lum);
        color = 1.0 - (1.0 - color) * (1.0 - tintAmount);
    }

    float darkFloor = mix(0.07, 0.09, saturate(lum * 2.5));
    float3 regimeTarget = mix(float3(darkFloor), float3(1.0), regime);
    color = mix(color, regimeTarget, uniforms.glassTintStrength * 0.73);

    float shadowScale = saturate(1.0 - lum * 0.8);
    float overallShadow = uniforms.overallShadowStrength * shadowScale;
    float edgeShadow = smoothstep(20.0, 0.0, distFromEdge) * uniforms.edgeShadowStrength * shadowScale;
    color = color * (1.0 - overallShadow - edgeShadow);
    float aa = saturate(0.5 - sdf / (edgeAA * 2.0));
    float borderInner = smoothstep(3.0, 0.3, distFromEdge);
    float borderOuter = saturate(distFromEdge / (edgeAA * 0.8));
    float borderMask = borderInner * borderOuter * aa;
    float2 q = abs(stretched) - halfSize + scaledCornerRadius;
    float2 borderNormal;
    if (max(q.x, q.y) < 0.0) {
        borderNormal = (q.x > q.y)
            ? float2(sign(stretched.x), 0.0)
            : float2(0.0, sign(stretched.y));
    } else {
        float2 w = max(q, 0.0);
        float len = length(w);
        borderNormal = len > 0.001 ? sign(stretched) * w / len : float2(0.0);
    }
    float2 lightDir = normalize(float2(1.0, 1.0));
    float dirFactor = abs(dot(borderNormal, lightDir));
    dirFactor = dirFactor * dirFactor;
    float borderDark = mix(0.10, 0.40, dirFactor);
    float borderLight = mix(0.62, 1.0, dirFactor) * mix(0.65, 1.0, lum);
    float borderBase = mix(borderDark, borderLight, regime);
    color = mix(color, float3(1.0), borderMask * borderBase);

    if (uniforms.hasContent > 0.5) {
        float2 contentUV;
        contentUV.x = (stretched.x / halfWidth + 1.0) * 0.5;
        contentUV.y = (stretched.y / halfHeight + 1.0) * 0.5;

        if (contentUV.x >= 0.0 && contentUV.x <= 1.0 &&
            contentUV.y >= 0.0 && contentUV.y <= 1.0) {
            float4 ct = contentTexture.sample(texSampler, contentUV);
            float3 glassPM = color * aa;
            float3 resultPM = ct.rgb + glassPM * (1.0 - ct.a);
            float resultA = ct.a + aa * (1.0 - ct.a);
            color = resultA > 0.001 ? resultPM / resultA : float3(0);
            aa = resultA;
        }
    }

    return float4(color, aa * uniforms.physOpacity);
}
