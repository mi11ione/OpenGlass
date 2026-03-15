#import "OGCompositor.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include <unordered_map>
#include <vector>
#include <algorithm>

struct CompositorVertex {
    float position[2];
    float texCoord[2];
    float opacity;
    float bgColor[4];
    float hasTexture;
};

struct CachedTexture {
    id<MTLTexture> texture;
    int lastFrame;
    size_t width;
    size_t height;
    size_t bytesPerRow;
};

struct FallbackCacheEntry {
    id<MTLTexture> texture;
    int width;
    int height;
    int lastFrame;
    bool subtree;
};

struct DrawRange {
    __unsafe_unretained id<MTLTexture> texture;
    uint32_t vertexStart;
    uint32_t vertexCount;
    CGRect worldClipRect;
};

struct RenderOp {
    enum Type : uint8_t { kDraw, kMaskBegin, kMaskEnd };
    Type type;
    uint32_t drawRangeStart;
    uint32_t drawRangeCount;
    __unsafe_unretained id<MTLTexture> maskTexture;
    CGAffineTransform inverseMaskTransform;
    CGRect maskBounds;
};

struct MaskBlitUniforms {
    simd_float2 viewportSize;
    simd_float2 captureOrigin;
    float invScale;
    float _pad;
    simd_float2 maskBoundsOrigin;
    simd_float2 maskBoundsInvSize;
    simd_float2 imCol0;
    simd_float2 imCol1;
    simd_float2 imTranslation;
    simd_float2 contentTexScale;
};

struct MaskStackEntry {
    __unsafe_unretained id<MTLTexture> maskTexture;
    CGAffineTransform inverseMaskTransform;
    CGRect maskBounds;
};

struct GradientLUTEntry {
    id<MTLTexture> texture;
    int lastFrame;
};

static const uint32_t kBitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
static const int kFrameBufferCount = 3;
static const int kMaxMaskNesting = 4;
static const size_t kMaxCacheBytes = 32 * 1024 * 1024;
static const size_t kEvictTargetBytes = 24 * 1024 * 1024;

static void drawShapeLayer(CAShapeLayer *layer, CGContextRef ctx) {
    CGPathRef path = layer.path;
    if (!path) return;

    CGColorRef fill = layer.fillColor;
    if (fill && CGColorGetAlpha(fill) > 0.001) {
        CGContextSaveGState(ctx);
        CGContextSetFillColorWithColor(ctx, fill);
        CGContextAddPath(ctx, path);
        if ([layer.fillRule isEqualToString:kCAFillRuleEvenOdd]) {
            CGContextEOFillPath(ctx);
        } else {
            CGContextFillPath(ctx);
        }
        CGContextRestoreGState(ctx);
    }

    CGColorRef stroke = layer.strokeColor;
    if (stroke && CGColorGetAlpha(stroke) > 0.001 && layer.lineWidth > 0) {
        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, stroke);
        CGContextSetLineWidth(ctx, layer.lineWidth);
        CGContextSetMiterLimit(ctx, layer.miterLimit);

        NSString *cap = layer.lineCap;
        if ([cap isEqualToString:kCALineCapRound])       CGContextSetLineCap(ctx, kCGLineCapRound);
        else if ([cap isEqualToString:kCALineCapSquare]) CGContextSetLineCap(ctx, kCGLineCapSquare);

        NSString *join = layer.lineJoin;
        if ([join isEqualToString:kCALineJoinRound])      CGContextSetLineJoin(ctx, kCGLineJoinRound);
        else if ([join isEqualToString:kCALineJoinBevel]) CGContextSetLineJoin(ctx, kCGLineJoinBevel);

        NSArray<NSNumber *> *dash = layer.lineDashPattern;
        if (dash.count > 0) {
            CGFloat *lengths = (CGFloat *)alloca(dash.count * sizeof(CGFloat));
            for (NSUInteger i = 0; i < dash.count; i++) lengths[i] = dash[i].doubleValue;
            CGContextSetLineDash(ctx, layer.lineDashPhase, lengths, dash.count);
        }

        CGContextAddPath(ctx, path);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }
}

static void drawGradientLayer(CAGradientLayer *layer, CGContextRef ctx, CGColorSpaceRef cs) {
    NSArray *colors = layer.colors;
    if (!colors.count) return;

    NSUInteger n = colors.count;
    CGFloat *comp = (CGFloat *)alloca(n * 4 * sizeof(CGFloat));
    CGFloat *locs = NULL;

    for (NSUInteger i = 0; i < n; i++) {
        CGColorRef c = (__bridge CGColorRef)colors[i];
        const CGFloat *src = CGColorGetComponents(c);
        size_t nc = CGColorGetNumberOfComponents(c);
        if (nc >= 4) {
            comp[i*4] = src[0]; comp[i*4+1] = src[1]; comp[i*4+2] = src[2]; comp[i*4+3] = src[3];
        } else if (nc >= 2) {
            comp[i*4] = src[0]; comp[i*4+1] = src[0]; comp[i*4+2] = src[0]; comp[i*4+3] = src[1];
        } else {
            comp[i*4] = 0; comp[i*4+1] = 0; comp[i*4+2] = 0; comp[i*4+3] = 1;
        }
    }

    NSArray<NSNumber *> *locArr = layer.locations;
    if (locArr.count == n) {
        locs = (CGFloat *)alloca(n * sizeof(CGFloat));
        for (NSUInteger i = 0; i < n; i++) locs[i] = locArr[i].doubleValue;
    }

    CGGradientRef gradient = CGGradientCreateWithColorComponents(cs, comp, locs, n);
    if (!gradient) return;

    CGRect b = layer.bounds;
    CGPoint start = { b.origin.x + layer.startPoint.x * b.size.width,
                      b.origin.y + layer.startPoint.y * b.size.height };
    CGPoint end   = { b.origin.x + layer.endPoint.x * b.size.width,
                      b.origin.y + layer.endPoint.y * b.size.height };

    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, b);

    if ([layer.type isEqualToString:kCAGradientLayerRadial]) {
        CGFloat r = hypot(end.x - start.x, end.y - start.y);
        CGContextDrawRadialGradient(ctx, gradient, start, 0, start, r,
            kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    } else if ([layer.type isEqualToString:kCAGradientLayerConic]) {
        NSUInteger steps = n * 64;
        CGFloat maxR = hypot(b.size.width, b.size.height);
        for (NSUInteger i = 0; i < steps; i++) {
            CGFloat a0 = ((CGFloat)i / steps) * 2.0 * M_PI;
            CGFloat a1 = ((CGFloat)(i + 1) / steps) * 2.0 * M_PI;
            CGFloat t = (CGFloat)i / steps;

            CGFloat r0, g0, b0, aa0;
            if (locs) {
                NSUInteger seg = 0;
                for (NSUInteger s = 0; s < n - 1; s++) {
                    if (t >= locs[s] && t <= locs[s + 1]) { seg = s; break; }
                }
                CGFloat segT = (locs[seg + 1] > locs[seg])
                    ? (t - locs[seg]) / (locs[seg + 1] - locs[seg]) : 0;
                r0  = comp[seg*4]   + (comp[(seg+1)*4]   - comp[seg*4])   * segT;
                g0  = comp[seg*4+1] + (comp[(seg+1)*4+1] - comp[seg*4+1]) * segT;
                b0  = comp[seg*4+2] + (comp[(seg+1)*4+2] - comp[seg*4+2]) * segT;
                aa0 = comp[seg*4+3] + (comp[(seg+1)*4+3] - comp[seg*4+3]) * segT;
            } else {
                CGFloat idx = t * (n - 1);
                NSUInteger seg = (NSUInteger)idx;
                if (seg >= n - 1) seg = n - 2;
                CGFloat segT = idx - seg;
                r0  = comp[seg*4]   + (comp[(seg+1)*4]   - comp[seg*4])   * segT;
                g0  = comp[seg*4+1] + (comp[(seg+1)*4+1] - comp[seg*4+1]) * segT;
                b0  = comp[seg*4+2] + (comp[(seg+1)*4+2] - comp[seg*4+2]) * segT;
                aa0 = comp[seg*4+3] + (comp[(seg+1)*4+3] - comp[seg*4+3]) * segT;
            }

            CGContextMoveToPoint(ctx, start.x, start.y);
            CGContextAddLineToPoint(ctx, start.x + cos(a0) * maxR, start.y + sin(a0) * maxR);
            CGContextAddLineToPoint(ctx, start.x + cos(a1) * maxR, start.y + sin(a1) * maxR);
            CGContextClosePath(ctx);

            CGContextSetRGBFillColor(ctx, r0, g0, b0, aa0);
            CGContextFillPath(ctx);
        }
    } else {
        CGContextDrawLinearGradient(ctx, gradient, start, end,
            kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    }

    CGContextRestoreGState(ctx);
    CGGradientRelease(gradient);
}

static void drawTextLayer(CATextLayer *layer, CGContextRef ctx) {
    id string = layer.string;
    if (!string) return;

    NSAttributedString *attrStr = nil;

    if ([string isKindOfClass:[NSAttributedString class]]) {
        attrStr = string;
    } else if ([string isKindOfClass:[NSString class]]) {
        CTFontRef font = NULL;
        CGFloat size = layer.fontSize;
        CFTypeRef fontRef = layer.font;

        if (fontRef) {
            CFTypeID tid = CFGetTypeID(fontRef);
            if (tid == CTFontGetTypeID())       font = (CTFontRef)CFRetain(fontRef);
            else if (tid == CGFontGetTypeID())   font = CTFontCreateWithGraphicsFont((CGFontRef)fontRef, size, NULL, NULL);
            else if (tid == CFStringGetTypeID()) font = CTFontCreateWithName((CFStringRef)fontRef, size, NULL);
        }
        if (!font) font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);

        CGColorRef fg = layer.foregroundColor;
        NSMutableDictionary *attrs = [NSMutableDictionary new];
        attrs[(id)kCTFontAttributeName] = (__bridge id)font;
        if (fg) attrs[(id)kCTForegroundColorAttributeName] = (__bridge id)fg;

        attrStr = [[NSAttributedString alloc] initWithString:(NSString *)string attributes:attrs];
        CFRelease(font);
    }

    if (!attrStr.length) return;

    CGRect b = layer.bounds;
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrStr);
    if (!fs) return;

    CGPathRef path = CGPathCreateWithRect(b, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    if (!frame) {
        CGPathRelease(path);
        CFRelease(fs);
        return;
    }

    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, 0, b.origin.y + b.size.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextTranslateCTM(ctx, 0, -b.origin.y);
    CTFrameDraw(frame, ctx);
    CGContextRestoreGState(ctx);

    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(fs);
}

static void renderSingleLayerContent(CALayer *layer, CGContextRef ctx, CGColorSpaceRef cs) {
    if ([layer isKindOfClass:[CAShapeLayer class]])         drawShapeLayer((CAShapeLayer *)layer, ctx);
    else if ([layer isKindOfClass:[CAGradientLayer class]]) drawGradientLayer((CAGradientLayer *)layer, ctx, cs);
    else if ([layer isKindOfClass:[CATextLayer class]])      drawTextLayer((CATextLayer *)layer, ctx);
    else                                                     [layer drawInContext:ctx];
}

static const int kGradientLUTWidth = 256;
static const int kMaxGradientCacheEntries = 4;

static uint64_t hashGradientData(const OGGradientData &gd, const OGGradientStop *stops) {
    uint64_t h = 14695981039346656037ULL;
    auto fnv = [&](const void *data, size_t len) {
        auto *p = (const uint8_t *)data;
        for (size_t i = 0; i < len; i++) {
            h ^= p[i];
            h *= 1099511628211ULL;
        }
    };
    uint16_t sc = gd.stopCount;
    fnv(&sc, sizeof(sc));
    fnv(stops + gd.stopOffset, gd.stopCount * sizeof(OGGradientStop));
    fnv(gd.startPoint, sizeof(gd.startPoint));
    fnv(gd.endPoint, sizeof(gd.endPoint));
    return h;
}

static void interpolateGradientColor(
    const OGGradientStop *stops, int count, float t,
    float &r, float &g, float &b, float &a
) {
    if (count <= 0) { r = g = b = a = 0; return; }
    if (t <= stops[0].location) {
        r = stops[0].r; g = stops[0].g; b = stops[0].b; a = stops[0].a;
        return;
    }
    if (t >= stops[count - 1].location) {
        r = stops[count - 1].r; g = stops[count - 1].g;
        b = stops[count - 1].b; a = stops[count - 1].a;
        return;
    }
    for (int i = 0; i < count - 1; i++) {
        if (t <= stops[i + 1].location) {
            float range = stops[i + 1].location - stops[i].location;
            float segT = (range > 1e-6f) ? (t - stops[i].location) / range : 0.0f;
            r = stops[i].r + (stops[i + 1].r - stops[i].r) * segT;
            g = stops[i].g + (stops[i + 1].g - stops[i].g) * segT;
            b = stops[i].b + (stops[i + 1].b - stops[i].b) * segT;
            a = stops[i].a + (stops[i + 1].a - stops[i].a) * segT;
            return;
        }
    }
    r = stops[count - 1].r; g = stops[count - 1].g;
    b = stops[count - 1].b; a = stops[count - 1].a;
}

@implementation OGCompositor {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLRenderPipelineState> _maskApplyPipeline;
    CGColorSpaceRef _colorSpace;

    std::unordered_map<CGImageRef, CachedTexture> _imageCache;
    std::unordered_map<void *, FallbackCacheEntry> _fallbackCache;
    std::unordered_map<uint64_t, GradientLUTEntry> _gradientCache;
    int _frameCount;
    size_t _totalCacheBytes;

    id<MTLTexture> _placeholderTexture;

    void *_scratchBuffer;
    size_t _scratchCapacity;

    std::vector<CompositorVertex> _vertices;
    std::vector<DrawRange> _drawRanges;
    std::vector<RenderOp> _renderOps;
    std::vector<MaskStackEntry> _maskStack;

    id<MTLBuffer> _frameBuffers[kFrameBufferCount];
    size_t _frameBufferSizes[kFrameBufferCount];
    int _frameIndex;
    size_t _frameWriteOffset;

    size_t _preparedOffset;
    bool _hasPreparedData;

    id<MTLTexture> _intermediateRTs[kMaxMaskNesting];
    int _intermediateRTWidth;
    int _intermediateRTHeight;
    int _irtAllocatedCount;
    int _irtEpochMaxWidth;
    int _irtEpochMaxHeight;
    int _irtEpochMaxDepth;
    int _irtFramesSinceCheck;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                          pipelineState:(id<MTLRenderPipelineState>)pipelineState
                      maskApplyPipeline:(nullable id<MTLRenderPipelineState>)maskApplyPipeline {
    self = [super init];
    if (!self) return nil;

    _device = device;
    _pipelineState = pipelineState;
    _maskApplyPipeline = maskApplyPipeline;
    _colorSpace = CGColorSpaceCreateDeviceRGB();
    _frameCount = 0;
    _totalCacheBytes = 0;
    _scratchBuffer = NULL;
    _scratchCapacity = 0;
    _frameIndex = 0;
    _frameWriteOffset = 0;
    _preparedOffset = 0;
    _hasPreparedData = false;
    _intermediateRTWidth = 0;
    _intermediateRTHeight = 0;
    _irtAllocatedCount = 0;
    _irtEpochMaxWidth = 0;
    _irtEpochMaxHeight = 0;
    _irtEpochMaxDepth = 0;
    _irtFramesSinceCheck = 0;
    memset(_frameBufferSizes, 0, sizeof(_frameBufferSizes));

    MTLTextureDescriptor *phDesc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    phDesc.usage = MTLTextureUsageShaderRead;
    phDesc.storageMode = MTLStorageModeShared;
    _placeholderTexture = [device newTextureWithDescriptor:phDesc];
    uint32_t white = 0xFFFFFFFF;
    [_placeholderTexture replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
                           mipmapLevel:0
                             withBytes:&white
                           bytesPerRow:4];

    _vertices.reserve(256 * 6);
    _drawRanges.reserve(64);
    _renderOps.reserve(32);

    return self;
}

- (void)dealloc {
    if (_colorSpace) CGColorSpaceRelease(_colorSpace);
    if (_scratchBuffer) free(_scratchBuffer);
}

- (void)beginFrame {
    _frameIndex = (_frameIndex + 1) % kFrameBufferCount;
    _frameWriteOffset = 0;
    _hasPreparedData = false;
    _frameCount++;

    if (_frameCount % 64 == 0) {
        [self _evictStaleEntries];
    }

    if (++_irtFramesSinceCheck >= 128) {
        _irtFramesSinceCheck = 0;
        if (_intermediateRTWidth > _irtEpochMaxWidth || _intermediateRTHeight > _irtEpochMaxHeight) {
            for (int i = 0; i < _irtAllocatedCount; i++) _intermediateRTs[i] = nil;
            _intermediateRTWidth = 0;
            _intermediateRTHeight = 0;
            _irtAllocatedCount = 0;
        } else if (_irtAllocatedCount > _irtEpochMaxDepth) {
            for (int i = _irtEpochMaxDepth; i < _irtAllocatedCount; i++) _intermediateRTs[i] = nil;
            _irtAllocatedCount = _irtEpochMaxDepth;
        }
        _irtEpochMaxWidth = 0;
        _irtEpochMaxHeight = 0;
        _irtEpochMaxDepth = 0;
    }
}

static void flushDrawBatch(uint32_t &batchStart,
                           std::vector<DrawRange> &drawRanges,
                           std::vector<RenderOp> &renderOps) {
    uint32_t batchCount = (uint32_t)drawRanges.size() - batchStart;
    if (batchCount > 0) {
        RenderOp op{};
        op.type = RenderOp::kDraw;
        op.drawRangeStart = batchStart;
        op.drawRangeCount = batchCount;
        renderOps.push_back(op);
    }
    batchStart = (uint32_t)drawRanges.size();
}

- (BOOL)prepareItems:(const OGRenderItem *)items
               count:(NSUInteger)count
           gradients:(const OGGradientData *)gradients
       gradientCount:(NSUInteger)gradientCount
       gradientStops:(const OGGradientStop *)stops
               scale:(CGFloat)scale
           fromIndex:(NSUInteger)startIndex {
    if (startIndex == 0) {
        _hasPreparedData = false;
        _vertices.clear();
        _drawRanges.clear();
        _renderOps.clear();
        _maskStack.clear();
    }

    if (startIndex >= count) return _hasPreparedData;
    if (count == 0) return NO;

    uint32_t batchStart = (uint32_t)_drawRanges.size();

    for (NSUInteger i = startIndex; i < count; i++) {
        const OGRenderItem &item = items[i];

        if (item.contentType == OGRenderItem::kMaskGroupBegin) {
            flushDrawBatch(batchStart, _drawRanges, _renderOps);

            id<MTLTexture> maskTex = nil;
            if (item.maskLayer) {
                maskTex = [self _fallbackTextureForLayer:item.maskLayer scale:scale renderSubtree:YES];
            }

            CGAffineTransform invMask = CGAffineTransformInvert(item.maskTransform);
            _maskStack.push_back({ maskTex, invMask, item.maskBounds });

            RenderOp op{};
            op.type = RenderOp::kMaskBegin;
            _renderOps.push_back(op);
            continue;
        }

        if (item.contentType == OGRenderItem::kMaskGroupEnd) {
            flushDrawBatch(batchStart, _drawRanges, _renderOps);

            if (!_maskStack.empty()) {
                const auto &entry = _maskStack.back();
                RenderOp op{};
                op.type = RenderOp::kMaskEnd;
                op.maskTexture = entry.maskTexture;
                op.inverseMaskTransform = entry.inverseMaskTransform;
                op.maskBounds = entry.maskBounds;
                _renderOps.push_back(op);
                _maskStack.pop_back();
            }
            continue;
        }

        id<MTLTexture> tex = nil;
        float hasTexFlag = 0.0f;

        if (item.contentType == OGRenderItem::kCGImage && item.cgImage) {
            tex = [self _textureForImage:item.cgImage];
            if (tex) hasTexFlag = 1.0f;
        } else if (item.contentType == OGRenderItem::kFallbackSubtree && item.fallbackLayer) {
            tex = [self _fallbackTextureForLayer:item.fallbackLayer scale:scale renderSubtree:YES];
            if (tex) hasTexFlag = 1.0f;
        } else if (item.contentType == OGRenderItem::kFallback && item.fallbackLayer) {
            tex = [self _fallbackTextureForLayer:item.fallbackLayer scale:scale renderSubtree:NO];
            if (tex) hasTexFlag = 1.0f;
        } else if (item.contentType == OGRenderItem::kLinearGradient &&
                   item.gradientIndex < gradientCount) {
            tex = [self _gradientLUTForData:gradients[item.gradientIndex] stops:stops];
            if (tex) hasTexFlag = 1.0f;
        }

        if (hasTexFlag < 0.5f && item.bgColor[3] < 0.001f) continue;

        id<MTLTexture> boundTexture = tex ?: _placeholderTexture;

        CGRect b = item.bounds;
        CGPoint corners[4] = {
            { b.origin.x, b.origin.y },
            { b.origin.x + b.size.width, b.origin.y },
            { b.origin.x, b.origin.y + b.size.height },
            { b.origin.x + b.size.width, b.origin.y + b.size.height }
        };

        float uvs[4][2];
        if (item.contentType == OGRenderItem::kLinearGradient && item.gradientIndex < gradientCount) {
            const auto &gd = gradients[item.gradientIndex];
            float sx = gd.startPoint[0], sy = gd.startPoint[1];
            float dx = gd.endPoint[0] - sx, dy = gd.endPoint[1] - sy;
            float len2 = dx * dx + dy * dy;
            float normCorners[4][2] = {
                { 0.0f, 0.0f }, { 1.0f, 0.0f },
                { 0.0f, 1.0f }, { 1.0f, 1.0f }
            };
            for (int j = 0; j < 4; j++) {
                float t = (len2 > 1e-8f)
                    ? ((normCorners[j][0] - sx) * dx + (normCorners[j][1] - sy) * dy) / len2
                    : 0.0f;
                uvs[j][0] = t;
                uvs[j][1] = 0.5f;
            }
        } else {
            CGRect cr = item.contentsRect;
            uvs[0][0] = (float)cr.origin.x;                          uvs[0][1] = (float)cr.origin.y;
            uvs[1][0] = (float)(cr.origin.x + cr.size.width);        uvs[1][1] = (float)cr.origin.y;
            uvs[2][0] = (float)cr.origin.x;                          uvs[2][1] = (float)(cr.origin.y + cr.size.height);
            uvs[3][0] = (float)(cr.origin.x + cr.size.width);        uvs[3][1] = (float)(cr.origin.y + cr.size.height);
        }

        float bg[4] = { item.bgColor[0], item.bgColor[1], item.bgColor[2], item.bgColor[3] };

        CompositorVertex v[4];
        for (int j = 0; j < 4; j++) {
            CGPoint world = CGPointApplyAffineTransform(corners[j], item.transform);
            v[j].position[0] = (float)world.x;
            v[j].position[1] = (float)world.y;
            v[j].texCoord[0] = uvs[j][0];
            v[j].texCoord[1] = uvs[j][1];
            v[j].opacity = item.opacity;
            memcpy(v[j].bgColor, bg, sizeof(bg));
            v[j].hasTexture = hasTexFlag;
        }

        uint32_t vertexStart = (uint32_t)_vertices.size();
        _vertices.push_back(v[0]);
        _vertices.push_back(v[1]);
        _vertices.push_back(v[2]);
        _vertices.push_back(v[1]);
        _vertices.push_back(v[3]);
        _vertices.push_back(v[2]);

        CGRect clipRect = item.clipRect;
        bool canMerge = false;
        if (!_drawRanges.empty()) {
            const auto &prev = _drawRanges.back();
            if (prev.texture == boundTexture &&
                memcmp(&prev.worldClipRect, &clipRect, sizeof(CGRect)) == 0) {
                canMerge = true;
            }
        }

        if (canMerge) {
            _drawRanges.back().vertexCount += 6;
        } else {
            _drawRanges.push_back({ boundTexture, vertexStart, 6, clipRect });
        }
    }

    flushDrawBatch(batchStart, _drawRanges, _renderOps);

    while (!_maskStack.empty()) {
        const auto &entry = _maskStack.back();
        RenderOp op{};
        op.type = RenderOp::kMaskEnd;
        op.maskTexture = entry.maskTexture;
        op.inverseMaskTransform = entry.inverseMaskTransform;
        op.maskBounds = entry.maskBounds;
        _renderOps.push_back(op);
        _maskStack.pop_back();
    }

    if (_vertices.empty()) return NO;

    size_t neededBytes = _vertices.size() * sizeof(CompositorVertex);
    size_t alignedBytes = (neededBytes + 15) & ~(size_t)15;

    if (_frameWriteOffset + alignedBytes > _frameBufferSizes[_frameIndex]) {
        size_t newCapacity = (_frameWriteOffset + alignedBytes) * 2;
        if (newCapacity < 64 * 1024) newCapacity = 64 * 1024;
        _frameBuffers[_frameIndex] = [_device newBufferWithLength:newCapacity
                                                          options:MTLResourceStorageModeShared];
        if (!_frameBuffers[_frameIndex]) return NO;
        _frameBufferSizes[_frameIndex] = newCapacity;
        _frameWriteOffset = 0;
    }

    id<MTLBuffer> buf = _frameBuffers[_frameIndex];
    _preparedOffset = _frameWriteOffset;
    memcpy((char *)buf.contents + _preparedOffset, _vertices.data(), neededBytes);
    _frameWriteOffset += alignedBytes;

    _hasPreparedData = true;
    return YES;
}

- (void)renderIntoTexture:(id<MTLTexture>)texture
              captureRect:(CGRect)captureRect
                    scale:(CGFloat)scale
            commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!_hasPreparedData || _renderOps.empty()) return;

    id<MTLBuffer> buf = _frameBuffers[_frameIndex];
    if (!buf) return;

    NSUInteger vpW = (NSUInteger)ceil(captureRect.size.width * scale);
    NSUInteger vpH = (NSUInteger)ceil(captureRect.size.height * scale);
    if (vpW > texture.width) vpW = texture.width;
    if (vpH > texture.height) vpH = texture.height;
    if (vpW == 0 || vpH == 0) return;

    float viewport[4] = {
        (float)captureRect.origin.x,
        (float)captureRect.origin.y,
        1.0f / (float)captureRect.size.width,
        1.0f / (float)captureRect.size.height
    };

    CGFloat cx = captureRect.origin.x;
    CGFloat cy = captureRect.origin.y;
    MTLScissorRect fullScissor = { 0, 0, vpW, vpH };

    struct TargetEntry {
        __unsafe_unretained id<MTLTexture> tex;
        bool cleared;
    };
    TargetEntry targetStack[kMaxMaskNesting + 1];
    int stackTop = 0;
    targetStack[0] = { texture, false };
    int intermediateIdx = 0;
    int skipDepth = 0;

    id<MTLRenderCommandEncoder> enc = nil;

    for (const auto &op : _renderOps) {
        switch (op.type) {

        case RenderOp::kDraw: {
            if (op.drawRangeCount == 0) break;

            if (!enc) {
                TargetEntry &entry = targetStack[stackTop];
                MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor new];
                rpd.colorAttachments[0].texture = entry.tex;
                if (!entry.cleared) {
                    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
                    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
                    entry.cleared = true;
                } else {
                    rpd.colorAttachments[0].loadAction = MTLLoadActionLoad;
                }
                rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

                enc = [commandBuffer renderCommandEncoderWithDescriptor:rpd];
                if (!enc) break;
                [enc setRenderPipelineState:_pipelineState];
                [enc setVertexBuffer:buf offset:_preparedOffset atIndex:0];
                [enc setVertexBytes:viewport length:sizeof(viewport) atIndex:1];
                [enc setViewport:(MTLViewport){ 0, 0, (double)vpW, (double)vpH, 0, 1 }];
            }

            uint32_t end = op.drawRangeStart + op.drawRangeCount;
            for (uint32_t r = op.drawRangeStart; r < end; r++) {
                const auto &range = _drawRanges[r];
                [enc setFragmentTexture:range.texture atIndex:0];

                if (!CGRectIsInfinite(range.worldClipRect)) {
                    CGFloat sx = (range.worldClipRect.origin.x - cx) * scale;
                    CGFloat sy = (range.worldClipRect.origin.y - cy) * scale;
                    CGFloat sw = range.worldClipRect.size.width * scale;
                    CGFloat sh = range.worldClipRect.size.height * scale;
                    NSUInteger x0 = (NSUInteger)fmax(0, sx);
                    NSUInteger y0 = (NSUInteger)fmax(0, sy);
                    NSUInteger x1 = (NSUInteger)fmin(vpW, ceil(sx + sw));
                    NSUInteger y1 = (NSUInteger)fmin(vpH, ceil(sy + sh));
                    if (x1 <= x0 || y1 <= y0) continue;
                    [enc setScissorRect:(MTLScissorRect){ x0, y0, x1 - x0, y1 - y0 }];
                } else {
                    [enc setScissorRect:fullScissor];
                }

                [enc drawPrimitives:MTLPrimitiveTypeTriangle
                        vertexStart:range.vertexStart
                        vertexCount:range.vertexCount];
            }
            break;
        }

        case RenderOp::kMaskBegin: {
            if (enc) { [enc endEncoding]; enc = nil; }

            if (intermediateIdx < kMaxMaskNesting &&
                [self _ensureIntermediateRT:intermediateIdx width:(int)vpW height:(int)vpH]) {
                stackTop++;
                targetStack[stackTop] = { _intermediateRTs[intermediateIdx], false };
                intermediateIdx++;
            } else {
                skipDepth++;
            }
            break;
        }

        case RenderOp::kMaskEnd: {
            if (enc) { [enc endEncoding]; enc = nil; }

            if (skipDepth > 0) {
                skipDepth--;
                break;
            }

            if (stackTop <= 0) break;

            id<MTLTexture> intermediateRT = targetStack[stackTop].tex;
            stackTop--;
            intermediateIdx--;

            TargetEntry &parent = targetStack[stackTop];

            [self _blitMaskedContent:intermediateRT
                         maskTexture:op.maskTexture
                  inverseMaskTransform:op.inverseMaskTransform
                          maskBounds:op.maskBounds
                         intoTexture:parent.tex
                             cleared:&parent.cleared
                         captureRect:captureRect
                               scale:scale
                       commandBuffer:commandBuffer
                                 vpW:vpW
                                 vpH:vpH];
            break;
        }

        }
    }

    if (enc) {
        [enc endEncoding];
    }
}

- (void)_blitMaskedContent:(id<MTLTexture>)contentTexture
               maskTexture:(id<MTLTexture>)maskTexture
        inverseMaskTransform:(CGAffineTransform)invMask
                maskBounds:(CGRect)maskBounds
               intoTexture:(id<MTLTexture>)target
                   cleared:(bool *)clearedFlag
               captureRect:(CGRect)captureRect
                     scale:(CGFloat)scale
             commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                       vpW:(NSUInteger)vpW
                       vpH:(NSUInteger)vpH {
    if (!_maskApplyPipeline || !contentTexture) return;

    if (!maskTexture) return;

    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor new];
    rpd.colorAttachments[0].texture = target;
    if (!*clearedFlag) {
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
        *clearedFlag = true;
    } else {
        rpd.colorAttachments[0].loadAction = MTLLoadActionLoad;
    }
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> enc = [commandBuffer renderCommandEncoderWithDescriptor:rpd];
    if (!enc) return;

    [enc setRenderPipelineState:_maskApplyPipeline];
    [enc setViewport:(MTLViewport){ 0, 0, (double)vpW, (double)vpH, 0, 1 }];

    float mbw = (float)maskBounds.size.width;
    float mbh = (float)maskBounds.size.height;

    MaskBlitUniforms uniforms;
    uniforms.viewportSize = simd_make_float2((float)vpW, (float)vpH);
    uniforms.captureOrigin = simd_make_float2((float)captureRect.origin.x, (float)captureRect.origin.y);
    uniforms.invScale = 1.0f / (float)scale;
    uniforms._pad = 0;
    uniforms.maskBoundsOrigin = simd_make_float2((float)maskBounds.origin.x, (float)maskBounds.origin.y);
    uniforms.maskBoundsInvSize = simd_make_float2(
        mbw > 0.001f ? 1.0f / mbw : 0.0f,
        mbh > 0.001f ? 1.0f / mbh : 0.0f
    );
    uniforms.imCol0 = simd_make_float2((float)invMask.a, (float)invMask.b);
    uniforms.imCol1 = simd_make_float2((float)invMask.c, (float)invMask.d);
    uniforms.imTranslation = simd_make_float2((float)invMask.tx, (float)invMask.ty);
    uniforms.contentTexScale = simd_make_float2(
        (float)vpW / (float)contentTexture.width,
        (float)vpH / (float)contentTexture.height
    );

    [enc setFragmentTexture:contentTexture atIndex:0];
    [enc setFragmentTexture:maskTexture atIndex:1];
    [enc setFragmentBytes:&uniforms length:sizeof(MaskBlitUniforms) atIndex:0];

    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
}

- (BOOL)_ensureIntermediateRT:(int)index width:(int)width height:(int)height {
    if (width > _irtEpochMaxWidth) _irtEpochMaxWidth = width;
    if (height > _irtEpochMaxHeight) _irtEpochMaxHeight = height;
    if (index >= _irtEpochMaxDepth) _irtEpochMaxDepth = index + 1;

    if (index < _irtAllocatedCount &&
        _intermediateRTWidth >= width && _intermediateRTHeight >= height) {
        return YES;
    }

    if (_intermediateRTWidth < width || _intermediateRTHeight < height) {
        int newW = MAX(_intermediateRTWidth, width);
        int newH = MAX(_intermediateRTHeight, height);
        for (int i = 0; i < _irtAllocatedCount; i++) _intermediateRTs[i] = nil;
        _irtAllocatedCount = 0;
        _intermediateRTWidth = newW;
        _intermediateRTHeight = newH;
    }

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                    width:_intermediateRTWidth
                                   height:_intermediateRTHeight
                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModePrivate;

    for (int i = _irtAllocatedCount; i <= index; i++) {
        _intermediateRTs[i] = [_device newTextureWithDescriptor:desc];
        if (!_intermediateRTs[i]) return NO;
    }
    _irtAllocatedCount = index + 1;
    return YES;
}

- (nullable id<MTLTexture>)_textureForImage:(CGImageRef)image {
    size_t w = CGImageGetWidth(image);
    size_t h = CGImageGetHeight(image);
    size_t srcBpr = CGImageGetBytesPerRow(image);

    auto it = _imageCache.find(image);
    if (it != _imageCache.end()) {
        if (it->second.width == w && it->second.height == h && it->second.bytesPerRow == srcBpr) {
            it->second.lastFrame = _frameCount;
            return it->second.texture;
        }
        _totalCacheBytes -= it->second.width * it->second.height * 4;
        _imageCache.erase(it);
    }

    if (w == 0 || h == 0) return nil;

    size_t bpr = w * 4;
    size_t totalBytes = bpr * h;

    if (_scratchCapacity < totalBytes) {
        if (_scratchBuffer) free(_scratchBuffer);
        _scratchBuffer = malloc(totalBytes);
        _scratchCapacity = _scratchBuffer ? totalBytes : 0;
        if (!_scratchBuffer) return nil;
    }

    CGContextRef ctx = CGBitmapContextCreate(_scratchBuffer, w, h, 8, bpr, _colorSpace, kBitmapInfo);
    if (!ctx) return nil;

    CGContextTranslateCTM(ctx, 0, (CGFloat)h);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
    CGContextRelease(ctx);

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                    width:w
                                   height:h
                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModeShared;

    id<MTLTexture> tex = [_device newTextureWithDescriptor:desc];
    if (!tex) return nil;

    [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:_scratchBuffer bytesPerRow:bpr];

    _imageCache[image] = { tex, _frameCount, w, h, srcBpr };
    _totalCacheBytes += w * h * 4;
    [self _evictCachesIfNeeded];
    return tex;
}

- (nullable id<MTLTexture>)_fallbackTextureForLayer:(CALayer *)layer scale:(CGFloat)scale renderSubtree:(BOOL)renderSubtree {
    CGSize size = layer.bounds.size;
    int pw = (int)ceil(size.width * scale);
    int ph = (int)ceil(size.height * scale);
    if (pw <= 0 || ph <= 0) return nil;

    void *key = (__bridge void *)layer;
    auto it = _fallbackCache.find(key);
    if (it != _fallbackCache.end()) {
        auto &entry = it->second;
        if (entry.width == pw && entry.height == ph && entry.subtree == (bool)renderSubtree) {
            entry.lastFrame = _frameCount;
            return entry.texture;
        }
        _totalCacheBytes -= (size_t)entry.width * (size_t)entry.height * 4;
        _fallbackCache.erase(it);
    }

    size_t bpr = (size_t)pw * 4;
    size_t totalBytes = (size_t)ph * bpr;

    if (_scratchCapacity < totalBytes) {
        if (_scratchBuffer) free(_scratchBuffer);
        _scratchBuffer = malloc(totalBytes);
        _scratchCapacity = totalBytes;
        if (!_scratchBuffer) {
            _scratchCapacity = 0;
            return nil;
        }
    }

    memset(_scratchBuffer, 0, totalBytes);

    CGContextRef ctx = CGBitmapContextCreate(
        _scratchBuffer, pw, ph, 8, bpr, _colorSpace, kBitmapInfo);
    if (!ctx) return nil;

    CGContextTranslateCTM(ctx, 0, (CGFloat)ph);
    CGContextScaleCTM(ctx, scale, -scale);
    CGContextTranslateCTM(ctx, -layer.bounds.origin.x, -layer.bounds.origin.y);

    bool hasOpaqueContents = false;
    if (!renderSubtree && layer.contents) {
        CFTypeID tid = CFGetTypeID((__bridge CFTypeRef)layer.contents);
        hasOpaqueContents = (tid != CGImageGetTypeID());
    }

    if (renderSubtree || !layer.sublayers.count || hasOpaqueContents) {
        [layer renderInContext:ctx];
    } else {
        renderSingleLayerContent(layer, ctx, _colorSpace);
    }

    CGContextRelease(ctx);

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                    width:pw
                                   height:ph
                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModeShared;

    id<MTLTexture> tex = [_device newTextureWithDescriptor:desc];
    if (!tex) return nil;

    [tex replaceRegion:MTLRegionMake2D(0, 0, pw, ph) mipmapLevel:0
             withBytes:_scratchBuffer
           bytesPerRow:bpr];

    _fallbackCache[key] = { tex, pw, ph, _frameCount, (bool)renderSubtree };
    _totalCacheBytes += (size_t)pw * (size_t)ph * 4;
    [self _evictCachesIfNeeded];
    return tex;
}

- (nullable id<MTLTexture>)_gradientLUTForData:(const OGGradientData &)gd stops:(const OGGradientStop *)allStops {
    uint64_t hash = hashGradientData(gd, allStops);
    auto it = _gradientCache.find(hash);
    if (it != _gradientCache.end()) {
        it->second.lastFrame = _frameCount;
        return it->second.texture;
    }

    int w = kGradientLUTWidth;
    size_t bpr = (size_t)w * 4;

    if (_scratchCapacity < bpr) {
        if (_scratchBuffer) free(_scratchBuffer);
        _scratchBuffer = malloc(bpr);
        _scratchCapacity = _scratchBuffer ? bpr : 0;
        if (!_scratchBuffer) return nil;
    }

    uint8_t *pixels = (uint8_t *)_scratchBuffer;
    const OGGradientStop *stops = allStops + gd.stopOffset;
    int count = gd.stopCount;
    float invW = 1.0f / (float)(w - 1);

    for (int x = 0; x < w; x++) {
        float t = (float)x * invW;
        float r, g, b, a;
        interpolateGradientColor(stops, count, t, r, g, b, a);

        size_t off = x * 4;
        pixels[off + 0] = (uint8_t)(b * a * 255.0f + 0.5f);
        pixels[off + 1] = (uint8_t)(g * a * 255.0f + 0.5f);
        pixels[off + 2] = (uint8_t)(r * a * 255.0f + 0.5f);
        pixels[off + 3] = (uint8_t)(a * 255.0f + 0.5f);
    }

    id<MTLTexture> tex = nil;
    if ((int)_gradientCache.size() >= kMaxGradientCacheEntries) {
        auto oldest = _gradientCache.begin();
        for (auto ci = _gradientCache.begin(); ci != _gradientCache.end(); ++ci) {
            if (ci->second.lastFrame < oldest->second.lastFrame) oldest = ci;
        }
        tex = oldest->second.texture;
        _totalCacheBytes -= (size_t)w * 4;
        _gradientCache.erase(oldest);
    }

    if (!tex) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                        width:w
                                       height:1
                                    mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModeShared;
        tex = [_device newTextureWithDescriptor:desc];
        if (!tex) return nil;
    }

    [tex replaceRegion:MTLRegionMake2D(0, 0, w, 1)
           mipmapLevel:0
             withBytes:pixels
           bytesPerRow:bpr];

    _gradientCache[hash] = { tex, _frameCount };
    _totalCacheBytes += (size_t)w * 4;
    [self _evictCachesIfNeeded];
    return tex;
}

- (void)_evictStaleEntries {
    int threshold = _frameCount - 60;

    for (auto it = _imageCache.begin(); it != _imageCache.end(); ) {
        if (it->second.lastFrame < threshold) {
            _totalCacheBytes -= it->second.width * it->second.height * 4;
            it = _imageCache.erase(it);
        } else {
            ++it;
        }
    }

    for (auto it = _fallbackCache.begin(); it != _fallbackCache.end(); ) {
        if (it->second.lastFrame < threshold) {
            _totalCacheBytes -= (size_t)it->second.width * (size_t)it->second.height * 4;
            it = _fallbackCache.erase(it);
        } else {
            ++it;
        }
    }
}

- (void)_evictCachesIfNeeded {
    if (_totalCacheBytes <= kMaxCacheBytes) return;

    int recentThreshold = _frameCount - 3;

    struct Candidate {
        int lastFrame;
        size_t bytes;
        bool isImage;
        CGImageRef imageKey;
        void *fallbackKey;
    };

    std::vector<Candidate> candidates;
    candidates.reserve(_imageCache.size() + _fallbackCache.size());

    for (const auto &pair : _imageCache) {
        if (pair.second.lastFrame >= recentThreshold) continue;
        candidates.push_back({
            pair.second.lastFrame,
            pair.second.width * pair.second.height * 4,
            true, pair.first, nullptr
        });
    }
    for (const auto &pair : _fallbackCache) {
        if (pair.second.lastFrame >= recentThreshold) continue;
        candidates.push_back({
            pair.second.lastFrame,
            (size_t)pair.second.width * (size_t)pair.second.height * 4,
            false, nullptr, pair.first
        });
    }

    if (candidates.empty()) return;

    std::sort(candidates.begin(), candidates.end(),
              [](const Candidate &a, const Candidate &b) { return a.lastFrame < b.lastFrame; });

    for (const auto &c : candidates) {
        if (_totalCacheBytes <= kEvictTargetBytes) break;
        if (c.isImage) {
            _imageCache.erase(c.imageKey);
        } else {
            _fallbackCache.erase(c.fallbackKey);
        }
        _totalCacheBytes -= c.bytes;
    }
}

- (void)flush {
    _imageCache.clear();
    _fallbackCache.clear();
    _gradientCache.clear();
    _totalCacheBytes = 0;

    if (_scratchBuffer) {
        free(_scratchBuffer);
        _scratchBuffer = NULL;
        _scratchCapacity = 0;
    }

    for (int i = 0; i < kFrameBufferCount; i++) {
        _frameBuffers[i] = nil;
        _frameBufferSizes[i] = 0;
    }
    _frameWriteOffset = 0;
    _preparedOffset = 0;
    _hasPreparedData = false;

    for (int i = 0; i < kMaxMaskNesting; i++) {
        _intermediateRTs[i] = nil;
    }
    _intermediateRTWidth = 0;
    _intermediateRTHeight = 0;

    _vertices.clear();
    _vertices.shrink_to_fit();
    _drawRanges.clear();
    _drawRanges.shrink_to_fit();
    _renderOps.clear();
    _renderOps.shrink_to_fit();
    _maskStack.clear();
    _maskStack.shrink_to_fit();
}

@end
