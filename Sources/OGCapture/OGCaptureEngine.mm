#import "OGCaptureEngine.h"
#import "OGLayerTraversal.h"
#import "OGCompositor.h"
#include <unordered_map>

static const int kBufferCount = 2;
static const int kShrinkCheckInterval = 128;

@implementation OGCaptureEngine {
    id<MTLDevice> _device;

    id<MTLTexture> _renderTargets[kBufferCount];
    int _rtIndex;
    int _rtWidth;
    int _rtHeight;

    int _epochMaxWidth;
    int _epochMaxHeight;
    int _framesSinceCheck;

    OGCompositor *_compositor;
    std::vector<OGRenderItem> _traversalItems;
    std::vector<OGGradientData> _traversalGradients;
    std::vector<OGGradientStop> _traversalStops;
    std::unordered_map<const void *, uint32_t> _glassCutoffs;
    bool _traversalHasMasks;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (!self) return nil;
    _device = device;
    _rtIndex = -1;
    return self;
}

- (void)setCompositorPipeline:(id<MTLRenderPipelineState>)compositorPipeline {
    _compositorPipeline = compositorPipeline;
    if (compositorPipeline && !_compositor) {
        _compositor = [[OGCompositor alloc] initWithDevice:_device
                                            pipelineState:compositorPipeline
                                        maskApplyPipeline:_maskApplyPipeline];
    }
}

- (void)advanceFrame {
    _rtIndex = (_rtIndex + 1) % kBufferCount;
    [_compositor beginFrame];

    if (++_framesSinceCheck >= kShrinkCheckInterval) {
        _framesSinceCheck = 0;
        if (_rtWidth > _epochMaxWidth || _rtHeight > _epochMaxHeight) {
            for (int i = 0; i < kBufferCount; i++) _renderTargets[i] = nil;
            _rtWidth = 0;
            _rtHeight = 0;
        }
        _epochMaxWidth = 0;
        _epochMaxHeight = 0;
    }
}

- (void)traverseLayer:(CALayer *)rootLayer
       allGlassLayers:(NSSet<CALayer *> *)allGlass
               inRect:(CGRect)unionRect {
    OGTraverseLayerTreeShared(rootLayer, allGlass, unionRect, _traversalItems, _traversalGradients, _traversalStops, _glassCutoffs);

    _traversalHasMasks = false;
    for (const auto &item : _traversalItems) {
        if (item.contentType == OGRenderItem::kMaskGroupBegin) {
            _traversalHasMasks = true;
            break;
        }
    }
}

- (uint32_t)cutoffForGlassLayer:(CALayer *)glassLayer {
    const void *key = (__bridge const void *)glassLayer;
    auto it = _glassCutoffs.find(key);
    return (it != _glassCutoffs.end()) ? it->second : (uint32_t)_traversalItems.size();
}

- (BOOL)prepareForCutoff:(uint32_t)cutoff fromIndex:(uint32_t)fromIndex scale:(CGFloat)scale {
    if (!_compositor) return NO;
    NSUInteger count = MIN((NSUInteger)cutoff, _traversalItems.size());
    if (count == 0) return NO;
    NSUInteger start = _traversalHasMasks ? 0 : MIN((NSUInteger)fromIndex, count);
    return [_compositor prepareItems:_traversalItems.data()
                            count:count
                        gradients:_traversalGradients.data()
                    gradientCount:_traversalGradients.size()
                    gradientStops:_traversalStops.data()
                            scale:scale
                        fromIndex:start];
}

- (nullable id<MTLTexture>)renderCompositeInRect:(CGRect)rect
                                           scale:(CGFloat)scale
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    int pw = (int)ceil(rect.size.width * scale);
    int ph = (int)ceil(rect.size.height * scale);
    if (pw <= 0 || ph <= 0) return nil;

    if (![self _ensureRenderTargetFits:pw height:ph]) return nil;

    id<MTLTexture> target = _renderTargets[_rtIndex];
    if (!target) return nil;

    [_compositor renderIntoTexture:target
                       captureRect:rect
                             scale:scale
                     commandBuffer:commandBuffer];

    return target;
}

- (void)flush {
    [_compositor flush];
    for (int i = 0; i < kBufferCount; i++) {
        _renderTargets[i] = nil;
    }
    _rtWidth = 0;
    _rtHeight = 0;
    _traversalItems.clear();
    _traversalItems.shrink_to_fit();
    _traversalGradients.clear();
    _traversalGradients.shrink_to_fit();
    _traversalStops.clear();
    _traversalStops.shrink_to_fit();
    _glassCutoffs.clear();
}

- (BOOL)_ensureRenderTargetFits:(int)width height:(int)height {
    if (width > _epochMaxWidth) _epochMaxWidth = width;
    if (height > _epochMaxHeight) _epochMaxHeight = height;

    if (_rtWidth >= width && _rtHeight >= height && _renderTargets[0]) {
        return YES;
    }

    int newWidth = MAX(_rtWidth, width);
    int newHeight = MAX(_rtHeight, height);

    for (int i = 0; i < kBufferCount; i++) _renderTargets[i] = nil;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                    width:newWidth
                                   height:newHeight
                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModePrivate;

    for (int i = 0; i < kBufferCount; i++) {
        _renderTargets[i] = [_device newTextureWithDescriptor:desc];
        if (!_renderTargets[i]) {
            for (int j = 0; j < kBufferCount; j++) _renderTargets[j] = nil;
            _rtWidth = 0;
            _rtHeight = 0;
            return NO;
        }
    }

    _rtWidth = newWidth;
    _rtHeight = newHeight;
    return YES;
}

@end
