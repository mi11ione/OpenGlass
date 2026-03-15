#ifndef OGRenderItem_h
#define OGRenderItem_h

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

#ifdef __cplusplus

struct OGGradientStop {
    float r, g, b, a;
    float location;
};

struct OGGradientData {
    uint32_t stopOffset;
    uint16_t stopCount;
    float startPoint[2];
    float endPoint[2];
};

struct OGRenderItem {
    CGAffineTransform transform;
    CGRect bounds;
    CGRect worldBounds;
    CGRect clipRect;
    float opacity;

    enum ContentType : uint8_t {
        kNone,
        kCGImage,
        kFallback,
        kFallbackSubtree,
        kMaskGroupBegin,
        kMaskGroupEnd,
        kLinearGradient
    };
    ContentType contentType;

    CGImageRef cgImage;
    __unsafe_unretained CALayer *fallbackLayer;

    simd_float4 bgColor;
    CGRect contentsRect;

    __unsafe_unretained CALayer *maskLayer;
    CGAffineTransform maskTransform;
    CGRect maskBounds;

    uint32_t gradientIndex;
};

#endif
#endif
