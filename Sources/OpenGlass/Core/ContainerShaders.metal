#include "GlassShaderCommon.h"

struct GlassChild {
    float2 center;
    float2 halfSize;
    float4 cornerRadii;
    float stretchX;
    float stretchY;
    float rotation;
    float physicsOffsetX;
    float physicsOffsetY;
    float scale;
    float opacity;
    float tintColorR;
    float tintColorG;
    float tintColorB;
    float hasTint;
    float tintMode;
    float tintIntensity;
};

struct ContainerUniforms {
    float2 containerSize;
    float2 renderSize;
    float padding;
    float _padding1;
    float2 backgroundSize;
    float2 backgroundOffset;
    float blurRadius;
    float refractionStrength;
    float chromeStrength;
    float edgeBandMultiplier;
    float glassTintStrength;
    float zoom;
    float topHighlightStrength;
    float edgeShadowStrength;
    float overallShadowStrength;
    float isDarkMode;
    float spacing;
    int childCount;
};

float smin(float a, float b, float k) {
    if (k <= 0.0) return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float evaluateChildSDF(float2 pixelPos, constant GlassChild& child) {
    float2 physicsOffset = float2(child.physicsOffsetX, child.physicsOffsetY);
    float2 offsetPos = pixelPos - physicsOffset;
    float2 fromCenter = offsetPos - child.center;

    float cosR = cos(child.rotation);
    float sinR = sin(child.rotation);
    float2 rotated = float2(
        fromCenter.x * cosR - fromCenter.y * sinR,
        fromCenter.x * sinR + fromCenter.y * cosR
    );

    float2 stretched = rotated / float2(child.stretchX, child.stretchY);
    float2 scaledHalfSize = child.halfSize * child.scale;
    float4 scaledRadii = child.cornerRadii * child.scale;

    return sdRoundedBox(stretched, scaledHalfSize, scaledRadii);
}

int findClosestChild(float2 pixelPos, constant GlassChild* children, int count) {
    int closest = 0;
    float minDist = evaluateChildSDF(pixelPos, children[0]);

    for (int i = 1; i < count; i++) {
        float d = evaluateChildSDF(pixelPos, children[i]);
        if (d < minDist) {
            minDist = d;
            closest = i;
        }
    }
    return closest;
}

float computeBlendWeight(float sdfValue, float spacing) {
    float blendRadius = max(spacing * 2.0, 40.0);
    float normalized = sdfValue / blendRadius;
    float w = 1.0 / (1.0 + exp(normalized * 2.0));
    return w;
}

float3 computeBlendedTint(
    float2 pixelPos,
    constant GlassChild* children,
    int count,
    float spacing,
    float3 baseColor,
    thread bool& outHasTint
) {
    float3 blendedTint = float3(0);
    float totalWeight = 0;
    bool anyHasTint = false;

    for (int i = 0; i < count; i++) {
        if (children[i].hasTint > 0.5) {
            anyHasTint = true;
            float d = evaluateChildSDF(pixelPos, children[i]);
            float weight = computeBlendWeight(d, spacing);
            float3 tintColor = float3(children[i].tintColorR, children[i].tintColorG, children[i].tintColorB);
            blendedTint += tintColor * weight;
            totalWeight += weight;
        }
    }

    outHasTint = anyHasTint;

    if (!anyHasTint || totalWeight < 0.001) {
        return baseColor;
    }

    return blendedTint / totalWeight;
}

float computeBlendedOpacity(
    float2 pixelPos,
    constant GlassChild* children,
    int count,
    float spacing
) {
    float blendedOpacity = 0;
    float totalWeight = 0;

    for (int i = 0; i < count; i++) {
        float d = evaluateChildSDF(pixelPos, children[i]);
        float weight = computeBlendWeight(d, spacing);
        blendedOpacity += children[i].opacity * weight;
        totalWeight += weight;
    }

    return totalWeight > 0.001 ? blendedOpacity / totalWeight : 1.0;
}

float evaluateCombinedSDF(float2 pixelPos, constant GlassChild* children, int count, float spacing) {
    if (count <= 0) return 1000.0;

    float combined = evaluateChildSDF(pixelPos, children[0]);
    for (int i = 1; i < count; i++) {
        float childSDF = evaluateChildSDF(pixelPos, children[i]);
        combined = smin(combined, childSDF, spacing);
    }
    return combined;
}

float2 computeCombinedSDFGradient(float2 pixelPos, constant GlassChild* children, int count, float spacing) {
    float eps = 4.0;

    float dx = evaluateCombinedSDF(pixelPos + float2(eps, 0), children, count, spacing)
             - evaluateCombinedSDF(pixelPos - float2(eps, 0), children, count, spacing);
    float dy = evaluateCombinedSDF(pixelPos + float2(0, eps), children, count, spacing)
             - evaluateCombinedSDF(pixelPos - float2(0, eps), children, count, spacing);

    float2 grad = float2(dx, dy) / (2.0 * eps);
    float len = length(grad);
    return len > 0.001 ? grad / len : float2(0.0);
}

vertex GlassVertexOut containerVertexShader(uint vertexID [[vertex_id]]) {
    return glassVertexShader(vertexID);
}

fragment float4 containerFragmentShader(
    GlassVertexOut in [[stage_in]],
    texture2d<float, access::sample> backgroundTexture [[texture(0)]],
    constant ContainerUniforms& uniforms [[buffer(0)]],
    constant GlassChild* children [[buffer(1)]]
) {
    constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    if (uniforms.childCount <= 0) {
        discard_fragment();
    }

    float2 renderPixelPos = in.texCoord * uniforms.renderSize;
    float2 pixelPos = renderPixelPos - uniforms.padding;
    float combinedSDF = evaluateChildSDF(pixelPos, children[0]);

    for (int i = 1; i < uniforms.childCount; i++) {
        float childSDF = evaluateChildSDF(pixelPos, children[i]);
        combinedSDF = smin(combinedSDF, childSDF, uniforms.spacing);
    }

    if (combinedSDF > 0.0) {
        discard_fragment();
    }

    int closestChild = findClosestChild(pixelPos, children, uniforms.childCount);
    constant GlassChild& closest = children[closestChild];

    float distFromEdge = -combinedSDF;

    float totalWeight = 0.0;
    float blendedEffectiveSize = 0.0;
    for (int i = 0; i < uniforms.childCount; i++) {
        float d = evaluateChildSDF(pixelPos, children[i]);
        float w = computeBlendWeight(d, uniforms.spacing);
        float childSize = min(
            children[i].halfSize.x * 2.0 * children[i].stretchX,
            children[i].halfSize.y * 2.0 * children[i].stretchY
        ) * children[i].scale;
        blendedEffectiveSize += childSize * w;
        totalWeight += w;
    }
    blendedEffectiveSize = totalWeight > 0.001 ? blendedEffectiveSize / totalWeight : 50.0;

    float edgeBand = blendedEffectiveSize * uniforms.edgeBandMultiplier;

    float minDist1 = 10000.0;
    float minDist2 = 10000.0;
    for (int i = 0; i < uniforms.childCount; i++) {
        float d = evaluateChildSDF(pixelPos, children[i]);
        if (d < minDist1) {
            minDist2 = minDist1;
            minDist1 = d;
        } else if (d < minDist2) {
            minDist2 = d;
        }
    }
    float distDiff = abs(minDist2 - minDist1);
    float blendZoneFactor = 1.0 - smoothstep(0.0, uniforms.spacing * 1.5, distDiff);

    float edgeFactor = 1.0 - smoothstep(0.0, edgeBand, distFromEdge);
    edgeFactor = edgeFactor * edgeFactor * edgeFactor * 2.0;
    edgeFactor *= (1.0 - blendZoneFactor * 0.8);

    float2 sdfGradient = computeCombinedSDFGradient(pixelPos, children, uniforms.childCount, uniforms.spacing);
    float2 toCenter = -sdfGradient;

    float gradientStrength = length(sdfGradient);
    float gradientReliability = smoothstep(0.3, 0.7, gradientStrength);
    toCenter *= gradientReliability;

    float2 blendedMagOffset = float2(0.0);
    totalWeight = 0.0;
    for (int i = 0; i < uniforms.childCount; i++) {
        float d = evaluateChildSDF(pixelPos, children[i]);
        float w = computeBlendWeight(d, uniforms.spacing);

        float2 childCenter = children[i].center;
        float2 childHalfSize = children[i].halfSize * children[i].scale * float2(children[i].stretchX, children[i].stretchY);
        float2 fromCenter = pixelPos - childCenter;
        float2 normFromCenter = fromCenter / max(childHalfSize, float2(1.0));
        float distNorm = length(normFromCenter);
        float zoomFactor = max(0.0, 1.0 - distNorm * distNorm);
        float zoomStrength = uniforms.zoom - 1.0;
        float2 childMagOffset = -normFromCenter * zoomFactor * zoomStrength * min(childHalfSize.x, childHalfSize.y);

        blendedMagOffset += childMagOffset * w;
        totalWeight += w;
    }
    float2 magOffset = totalWeight > 0.001 ? blendedMagOffset / totalWeight : float2(0.0);

    float disp = edgeFactor * uniforms.refractionStrength * edgeBand;
    float chrome = edgeFactor * uniforms.chromeStrength;

    float2 redOff = toCenter * (disp + chrome) + magOffset;
    float2 greenOff = toCenter * disp + magOffset;
    float2 blueOff = toCenter * (disp - chrome) + magOffset;
    float2 baseUV = (uniforms.backgroundOffset + pixelPos) / uniforms.backgroundSize;
    float2 redUV = clamp(baseUV + redOff / uniforms.backgroundSize, float2(0.001), float2(0.999));
    float2 greenUV = clamp(baseUV + greenOff / uniforms.backgroundSize, float2(0.001), float2(0.999));
    float2 blueUV = clamp(baseUV + blueOff / uniforms.backgroundSize, float2(0.001), float2(0.999));
    float2 texelSize = 1.0 / uniforms.backgroundSize;

    float r = sampleBlurredChannel(backgroundTexture, texSampler, redUV, texelSize, uniforms.blurRadius, 0);
    float g = sampleBlurredChannel(backgroundTexture, texSampler, greenUV, texelSize, uniforms.blurRadius, 1);
    float b = sampleBlurredChannel(backgroundTexture, texSampler, blueUV, texelSize, uniforms.blurRadius, 2);
    float3 glassColor = float3(r, g, b);

    float3 baseTint = uniforms.isDarkMode > 0.5 ? float3(0.15) : float3(1.0);
    float3 color = mix(glassColor, baseTint, uniforms.glassTintStrength);

    bool anyChildHasTint = false;
    float3 blendedTint = computeBlendedTint(pixelPos, children, uniforms.childCount, uniforms.spacing, color, anyChildHasTint);
    if (anyChildHasTint) {
        color = applyTintBlend(color, blendedTint, closest.tintMode, closest.tintIntensity);
    }

    float overallShadow = uniforms.overallShadowStrength;
    float edgeShadow = smoothstep(20.0, 0.0, distFromEdge) * uniforms.edgeShadowStrength;
    color = color * (1.0 - overallShadow - edgeShadow);

    float blendedHighlight = 0.0;
    totalWeight = 0.0;
    for (int i = 0; i < uniforms.childCount; i++) {
        float d = evaluateChildSDF(pixelPos, children[i]);
        float w = computeBlendWeight(d, uniforms.spacing);

        float2 childCenter = children[i].center;
        float2 childHalfSize = children[i].halfSize * children[i].scale * float2(children[i].stretchX, children[i].stretchY);
        float2 fromCenter = pixelPos - childCenter;
        float normalizedY = -fromCenter.y / max(childHalfSize.y, 1.0);
        float childHighlight = max(0.0, normalizedY);

        blendedHighlight += childHighlight * w;
        totalWeight += w;
    }
    blendedHighlight = totalWeight > 0.001 ? blendedHighlight / totalWeight : 0.0;
    float topHighlight = blendedHighlight * uniforms.topHighlightStrength;
    color = mix(color, float3(1.0), topHighlight);

    float aa = 1.0 - smoothstep(-1.0, 0.5, combinedSDF);
    float blendedOpacity = computeBlendedOpacity(pixelPos, children, uniforms.childCount, uniforms.spacing);

    return float4(color, aa * blendedOpacity);
}
