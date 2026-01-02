#include "GlassShaderCommon.h"

struct Uniforms {
    float2 size;
    float2 renderSize;
    float padding;
    float2 offset;
    float2 backgroundSize;
    float4 cornerRadii;
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
    float3 tintColor;
    float hasTintColor;
    float tintMode;
    float tintIntensity;
    float scale;
    float opacity;
    float stretchX;
    float stretchY;
    float rotation;
    float physicsOffsetX;
    float physicsOffsetY;
};

vertex GlassVertexOut vertexShader(uint vertexID [[vertex_id]]) {
    return glassVertexShader(vertexID);
}

fragment float4 fragmentShader(
    GlassVertexOut in [[stage_in]],
    texture2d<float, access::sample> backgroundTexture [[texture(0)]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 uv = in.texCoord;
    float2 renderPixelPos = uv * uniforms.renderSize;
    float2 pixelPos = renderPixelPos - float2(uniforms.padding);

    float2 center = uniforms.size * 0.5;
    float2 offsetPos = pixelPos - float2(uniforms.physicsOffsetX, uniforms.physicsOffsetY);
    float2 fromCenter = offsetPos - center;

    float cosR = cos(uniforms.rotation);
    float sinR = sin(uniforms.rotation);
    float2 rotated = float2(
        fromCenter.x * cosR - fromCenter.y * sinR,
        fromCenter.x * sinR + fromCenter.y * cosR
    );

    float2 stretched = rotated / float2(uniforms.stretchX, uniforms.stretchY);

    float scale = uniforms.scale;
    float halfWidth = uniforms.size.x * 0.5 * scale;
    float halfHeight = uniforms.size.y * 0.5 * scale;
    float2 halfSize = float2(halfWidth, halfHeight);
    float4 scaledCornerRadii = uniforms.cornerRadii * scale;

    float sdf = sdRoundedBox(stretched, halfSize, scaledCornerRadii);

    if (sdf > 0.0) {
        discard_fragment();
    }

    float2 visualFromCenter = fromCenter;

    float distFromEdge = -sdf;
    float effectiveSize = min(uniforms.size.x * uniforms.stretchX, uniforms.size.y * uniforms.stretchY);
    float edgeBand = effectiveSize * scale * uniforms.edgeBandMultiplier;

    float edgeFactor = 1.0 - smoothstep(0.0, edgeBand, distFromEdge);
    edgeFactor = edgeFactor * edgeFactor * edgeFactor * 2.0;

    float visualHalfWidth = halfWidth * uniforms.stretchX;
    float visualHalfHeight = halfHeight * uniforms.stretchY;

    float localRadius = getCornerRadius(stretched, scaledCornerRadii);
    float insetX = min(localRadius, halfWidth);
    float insetY = min(localRadius, halfHeight);
    float scaledMinX = center.x - halfWidth + insetX;
    float scaledMaxX = center.x + halfWidth - insetX;
    float scaledMinY = center.y - halfHeight + insetY;
    float scaledMaxY = center.y + halfHeight - insetY;
    float2 nearestCenterPoint = float2(
        clamp(offsetPos.x, scaledMinX, scaledMaxX),
        clamp(offsetPos.y, scaledMinY, scaledMaxY)
    );

    float2 toCenter = nearestCenterPoint - offsetPos;
    float distToCenter = length(toCenter);
    toCenter = distToCenter > 0.001 ? toCenter / distToCenter : float2(0.0);

    float2 normFromCenter = visualFromCenter / float2(visualHalfWidth, visualHalfHeight);
    float distNorm = length(normFromCenter);
    float zoomFactor = max(0.0, 1.0 - distNorm * distNorm);
    float zoomStrength = uniforms.zoom - 1.0;
    float2 magOffset = -normFromCenter * zoomFactor * zoomStrength * min(visualHalfWidth, visualHalfHeight);

    float disp = edgeFactor * uniforms.refractionStrength * edgeBand;
    float chrome = edgeFactor * uniforms.chromeStrength;

    float2 redOff = toCenter * (disp + chrome) + magOffset;
    float2 greenOff = toCenter * disp + magOffset;
    float2 blueOff = toCenter * (disp - chrome) + magOffset;

    float2 redUV = (uniforms.offset + pixelPos + redOff) / uniforms.backgroundSize;
    float2 greenUV = (uniforms.offset + pixelPos + greenOff) / uniforms.backgroundSize;
    float2 blueUV = (uniforms.offset + pixelPos + blueOff) / uniforms.backgroundSize;

    redUV = clamp(redUV, float2(0.001), float2(0.999));
    greenUV = clamp(greenUV, float2(0.001), float2(0.999));
    blueUV = clamp(blueUV, float2(0.001), float2(0.999));

    float2 texelSize = 1.0 / uniforms.backgroundSize;
    float blurAmount = uniforms.blurRadius;

    float r = sampleBlurredChannel(backgroundTexture, texSampler, redUV, texelSize, blurAmount, 0);
    float g = sampleBlurredChannel(backgroundTexture, texSampler, greenUV, texelSize, blurAmount, 1);
    float b = sampleBlurredChannel(backgroundTexture, texSampler, blueUV, texelSize, blurAmount, 2);
    float3 glassColor = float3(r, g, b);

    float3 baseTint = uniforms.isDarkMode > 0.5 ? float3(0.15) : float3(1.0);
    float3 color = mix(glassColor, baseTint, uniforms.glassTintStrength);

    if (uniforms.hasTintColor > 0.5) {
        color = applyTintBlend(color, uniforms.tintColor, uniforms.tintMode, uniforms.tintIntensity);
    }

    float overallShadow = uniforms.overallShadowStrength;
    float edgeShadow = smoothstep(20.0, 0.0, distFromEdge) * uniforms.edgeShadowStrength;
    color = color * (1.0 - overallShadow - edgeShadow);

    float normalizedY = -visualFromCenter.y / visualHalfHeight;
    float topHighlight = max(0.0, normalizedY) * uniforms.topHighlightStrength;
    color = mix(color, float3(1.0), topHighlight);

    float aa = 1.0 - smoothstep(-1.0, 0.5, sdf);

    return float4(color, aa * uniforms.opacity);
}
