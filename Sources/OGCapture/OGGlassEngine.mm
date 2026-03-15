#import "OGGlassEngine.h"
#import "OGCaptureEngine.h"
#import <UIKit/UIKit.h>
#import <simd/simd.h>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <cmath>

struct GlassUniforms {
    simd_float2 size;
    simd_float2 renderSize;
    simd_float2 offset;
    simd_float2 backgroundSize;
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

struct OGPhysicsState {
    float scale = 1.0f, scaleVel = 0.0f;
    float opacity = 1.0f, opacityVel = 0.0f;
    float stretchX = 1.0f, stretchY = 1.0f;
    float stretchXVel = 0.0f, stretchYVel = 0.0f;
    float rotation = 0.0f, rotationVel = 0.0f;
    float offsetX = 0.0f, offsetY = 0.0f;
    float offsetXVel = 0.0f, offsetYVel = 0.0f;
    float smoothVelX = 0.0f, smoothVelY = 0.0f;

    bool touchActive = false;
    float dragStartX = 0.0f, dragStartY = 0.0f;
    float dragCurrentX = 0.0f, dragCurrentY = 0.0f;
    float dragVelX = 0.0f, dragVelY = 0.0f;

    OGPhysicsTransformBlock transformBlock = nil;
    OGLuminanceBlock luminanceBlock = nil;
    float lastLuminance = 0.5f;
    bool isDarkMode = false;

    float tintRegime = 0.0f;
    float tintRegimeVel = 0.0f;
    float regimeTarget = 0.0f;
    float regimeHoldTimer = 0.0f;
};

static inline void ogSpring(float &val, float &vel, float target,
                             float k, float d, float dt) {
    float accel = -k * (val - target) - d * vel;
    vel += accel * dt;
    val += vel * dt;
}

static inline void ogAngularSpring(float &val, float &vel, float target,
                                    float k, float d, float dt) {
    float disp = val - target;
    const float pi = 3.14159265f;
    while (disp > pi) disp -= 2 * pi;
    while (disp < -pi) disp += 2 * pi;
    float accel = -k * disp - d * vel;
    vel += accel * dt;
    val += vel * dt;
    while (val > pi) val -= 2 * pi;
    while (val < -pi) val += 2 * pi;
}

static void updateFreePhysics(OGPhysicsState &p, const OGGlassConfig &c, float dt) {
    float vx = p.smoothVelX, vy = p.smoothVelY;
    float speed = sqrtf(vx * vx + vy * vy);

    float tSX = 1.0f, tSY = 1.0f, tRot = 0.0f;

    if (speed > 1.0f) {
        float dx = vx / speed, dy = vy / speed;
        float stretch = fminf(speed * c.velocityStretchSensitivity, c.maxStretch - 1.0f);
        float compress = 1.0f - fminf(speed * c.velocityStretchSensitivity * 0.6f, 1.0f - c.minStretch);
        float ax = fabsf(dx), ay = fabsf(dy);

        tSX = 1.0f + stretch * ax - (1.0f - compress) * ay;
        tSY = 1.0f + stretch * ay - (1.0f - compress) * ax;
        tSX = fmaxf(c.minStretch, fminf(c.maxStretch, tSX));
        tSY = fmaxf(c.minStretch, fminf(c.maxStretch, tSY));

        tRot = -vx * c.velocityRotationSensitivity;
        tRot = fmaxf(-c.maxRotation, fminf(c.maxRotation, tRot));
    }

    ogSpring(p.stretchX, p.stretchXVel, tSX, c.stretchStiffness, c.stretchDamping, dt);
    ogSpring(p.stretchY, p.stretchYVel, tSY, c.stretchStiffness, c.stretchDamping, dt);
    ogSpring(p.offsetX, p.offsetXVel, 0, c.offsetStiffness, c.offsetDamping, dt);
    ogSpring(p.offsetY, p.offsetYVel, 0, c.offsetStiffness, c.offsetDamping, dt);
    ogAngularSpring(p.rotation, p.rotationVel, tRot, c.rotationStiffness, c.rotationDamping, dt);
}

static void updateAnchoredPhysics(OGPhysicsState &p, const OGGlassConfig &c, float dt) {
    float tSX = 1.0f, tSY = 1.0f;
    float tOX = 0.0f, tOY = 0.0f, tRot = 0.0f;

    if (p.touchActive) {
        float dragX = p.dragCurrentX - p.dragStartX;
        float dragY = p.dragCurrentY - p.dragStartY;
        float dragDist = sqrtf(dragX * dragX + dragY * dragY);

        const float pressSquish = 0.97f;
        tSX = pressSquish;
        tSY = pressSquish;

        if (dragDist > 1.0f) {
            float dx = dragX / dragDist, dy = dragY / dragDist;
            float strAmt = fminf(dragDist * c.anchoredStretchSensitivity, c.anchoredMaxStretch - 1.0f);
            float xf = fabsf(dx) * fabsf(dx), yf = fabsf(dy) * fabsf(dy);

            tSX = pressSquish + strAmt * xf - strAmt * 0.2f * yf;
            tSY = pressSquish + strAmt * yf - strAmt * 0.2f * xf;
            tSX = fmaxf(0.85f, tSX);
            tSY = fmaxf(0.85f, tSY);

            float offF = 1.0f - 1.0f / (1.0f + dragDist * c.anchoredOffsetStiffness);
            tOX = c.anchoredMaxOffset * offF * dx;
            tOY = c.anchoredMaxOffset * offF * dy;

            tRot = -dx * strAmt * 0.12f;
            tRot = fmaxf(-c.maxRotation, fminf(c.maxRotation, tRot));
        }
    }

    ogSpring(p.stretchX, p.stretchXVel, tSX, c.stretchStiffness, c.stretchDamping, dt);
    ogSpring(p.stretchY, p.stretchYVel, tSY, c.stretchStiffness, c.stretchDamping, dt);
    ogSpring(p.offsetX, p.offsetXVel, tOX, c.offsetStiffness, c.offsetDamping, dt);
    ogSpring(p.offsetY, p.offsetYVel, tOY, c.offsetStiffness, c.offsetDamping, dt);
    ogAngularSpring(p.rotation, p.rotationVel, tRot, c.rotationStiffness, c.rotationDamping, dt);
}

static void updatePhysics(OGPhysicsState &p, const OGGlassConfig &c, float dt) {
    float threshold;
    if (p.isDarkMode) {
        threshold = p.regimeTarget > 0.5f ? 0.6f : 0.9f;
    } else {
        threshold = p.regimeTarget > 0.5f ? 0.2f : 0.5f;
    }
    float wantRegime = p.lastLuminance > threshold ? 1.0f : 0.0f;
    if (wantRegime != p.regimeTarget) {
        p.regimeHoldTimer += dt;
        if (p.regimeHoldTimer >= 0.15f) {
            p.regimeTarget = wantRegime;
            p.regimeHoldTimer = 0.0f;
        }
    } else {
        p.regimeHoldTimer = 0.0f;
    }
    ogSpring(p.tintRegime, p.tintRegimeVel, p.regimeTarget, 200.0f, 22.0f, dt);
    p.tintRegime = fmaxf(0.0f, fminf(1.0f, p.tintRegime));

    if (c.physicsMode == OGPhysicsModeNone) return;

    p.smoothVelX += 0.3f * (p.dragVelX - p.smoothVelX);
    p.smoothVelY += 0.3f * (p.dragVelY - p.smoothVelY);
    p.dragVelX = 0;
    p.dragVelY = 0;

    float targetScale = 1.0f, targetOpacity = 1.0f;
    if (p.touchActive) {
        targetScale = c.pressedScale;
        targetOpacity = c.pressedOpacity;
    }
    ogSpring(p.scale, p.scaleVel, targetScale, c.scaleStiffness, c.scaleDamping, dt);
    ogSpring(p.opacity, p.opacityVel, targetOpacity, c.opacityStiffness, c.opacityDamping, dt);
    p.opacity = fmaxf(0.0f, fminf(1.0f, p.opacity));

    switch (c.physicsMode) {
        case OGPhysicsModePress:
            ogSpring(p.stretchX, p.stretchXVel, 1.0f, c.stretchStiffness, c.stretchDamping, dt);
            ogSpring(p.stretchY, p.stretchYVel, 1.0f, c.stretchStiffness, c.stretchDamping, dt);
            ogSpring(p.offsetX, p.offsetXVel, 0, c.offsetStiffness, c.offsetDamping, dt);
            ogSpring(p.offsetY, p.offsetYVel, 0, c.offsetStiffness, c.offsetDamping, dt);
            ogSpring(p.rotation, p.rotationVel, 0, c.rotationStiffness, c.rotationDamping, dt);
            break;
        case OGPhysicsModeFree:
            updateFreePhysics(p, c, dt);
            break;
        case OGPhysicsModeAnchored:
            updateAnchoredPhysics(p, c, dt);
            break;
        default:
            break;
    }
}

static const int kAvgLumBufferCount = 2;

struct GlassElement {
    __unsafe_unretained UIView *sourceView;
    __unsafe_unretained CALayer *exclusionLayer;
    CAMetalLayer *metalLayer;
    OGGlassConfig config;
    OGPhysicsState physics;
    id<MTLTexture> contentTexture;
    id<MTLBuffer> avgLumBuffers[kAvgLumBufferCount];
    int avgLumIndex = 0;
};

struct SourceGroup {
    __unsafe_unretained UIView *source;
    std::vector<UIView *> views;
    std::vector<GlassElement *> configs;
    std::vector<CGRect> cachedRects;
    std::vector<uint32_t> cutoffs;
};

static OGGlassEngine *sShared = nil;

struct LumUniforms {
    simd_float2 offset;
    simd_float2 size;
    simd_float2 backgroundSize;
};

@implementation OGGlassEngine {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _glassPipeline;
    id<MTLComputePipelineState> _lumComputePipeline;
    OGCaptureEngine *_captureEngine;

    CADisplayLink *_displayLink;
    CGFloat _screenScale;
    CFTimeInterval _previousTimestamp;

    NSHashTable<UIView *> *_viewSet;
    std::unordered_map<const void *, GlassElement> _elements;
    std::vector<const void *> _pendingRemovals;
    std::vector<SourceGroup> _groupVec;
    NSMutableSet<CALayer *> *_scratchGlassLayers;

}

+ (void)setupWithDevice:(id<MTLDevice>)device
          glassPipeline:(id<MTLRenderPipelineState>)glassPipeline
     compositorPipeline:(id<MTLRenderPipelineState>)compositorPipeline
      maskApplyPipeline:(id<MTLRenderPipelineState>)maskApplyPipeline
    lumComputePipeline:(id<MTLComputePipelineState>)lumComputePipeline {
    if (sShared) return;
    sShared = [[OGGlassEngine alloc] _initWithDevice:device
                                       glassPipeline:glassPipeline
                                  compositorPipeline:compositorPipeline
                                   maskApplyPipeline:maskApplyPipeline
                                  lumComputePipeline:lumComputePipeline];
}

+ (nullable OGGlassEngine *)shared { return sShared; }

- (nullable instancetype)_initWithDevice:(id<MTLDevice>)device
                           glassPipeline:(id<MTLRenderPipelineState>)glassPipeline
                      compositorPipeline:(id<MTLRenderPipelineState>)compositorPipeline
                       maskApplyPipeline:(id<MTLRenderPipelineState>)maskApplyPipeline
                      lumComputePipeline:(id<MTLComputePipelineState>)lumComputePipeline {
    self = [super init];
    if (!self) return nil;
    _device = device;
    _glassPipeline = glassPipeline;
    _lumComputePipeline = lumComputePipeline;
    _commandQueue = [device newCommandQueue];
    if (!_commandQueue) return nil;
    _captureEngine = [[OGCaptureEngine alloc] initWithDevice:device];
    if (!_captureEngine) return nil;
    _captureEngine.maskApplyPipeline = maskApplyPipeline;
    _captureEngine.compositorPipeline = compositorPipeline;
    _viewSet = [NSHashTable weakObjectsHashTable];
    _screenScale = [UIScreen mainScreen].scale;
    _scratchGlassLayers = [NSMutableSet set];
    return self;
}

- (void)registerView:(UIView *)view {
    const void *key = (__bridge const void *)view;

    auto prIt = std::find(_pendingRemovals.begin(), _pendingRemovals.end(), key);
    if (prIt != _pendingRemovals.end()) _pendingRemovals.erase(prIt);

    if (_elements.count(key)) return;
    GlassElement elem{};
    elem.config = OGGlassConfigDefault();
    for (int i = 0; i < kAvgLumBufferCount; i++) {
        elem.avgLumBuffers[i] = [_device newBufferWithLength:sizeof(float)
                                                     options:MTLResourceStorageModeShared];
        float init = 0.5f;
        memcpy(elem.avgLumBuffers[i].contents, &init, sizeof(float));
    }
    _elements[key] = elem;
    [_viewSet addObject:view];
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_tick:)];
        if (@available(iOS 15.0, *)) {
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
        }
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)unregisterView:(UIView *)view {
    const void *key = (__bridge const void *)view;
    _pendingRemovals.push_back(key);
    [_viewSet removeObject:view];
    if (_viewSet.count == 0 && _displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
        _previousTimestamp = 0;
        [self _flushPendingRemovals];
        [_captureEngine flush];
    }
}

#define ELEM_FOR_VIEW(view) \
    const void *key = (__bridge const void *)view; \
    auto it = _elements.find(key); \
    if (it == _elements.end()) return; \
    auto &elem = it->second;

- (void)setConfig:(OGGlassConfig)config forView:(UIView *)view { ELEM_FOR_VIEW(view); elem.config = config; }
- (void)setSourceView:(nullable UIView *)sv forView:(UIView *)view { ELEM_FOR_VIEW(view); elem.sourceView = sv; }
- (void)setExclusionLayer:(nullable CALayer *)l forView:(UIView *)view { ELEM_FOR_VIEW(view); elem.exclusionLayer = l; }
- (void)setMetalLayer:(CAMetalLayer *)ml forView:(UIView *)view { ELEM_FOR_VIEW(view); elem.metalLayer = ml; }

- (void)setTouchActive:(BOOL)active forView:(UIView *)view position:(CGPoint)position {
    ELEM_FOR_VIEW(view);
    auto &p = elem.physics;
    if (active && !p.touchActive) {
        p.dragStartX = (float)position.x;
        p.dragStartY = (float)position.y;
        p.dragVelX = 0;
        p.dragVelY = 0;
        p.smoothVelX = 0;
        p.smoothVelY = 0;
    }
    if (!active && p.touchActive) {
        p.dragVelX = 0;
        p.dragVelY = 0;
    }
    p.touchActive = active;
    p.dragCurrentX = (float)position.x;
    p.dragCurrentY = (float)position.y;
}

- (void)setDragVelocity:(CGPoint)velocity forView:(UIView *)view {
    ELEM_FOR_VIEW(view);
    elem.physics.dragVelX = (float)velocity.x;
    elem.physics.dragVelY = (float)velocity.y;
}

- (void)setPhysicsTransformBlock:(nullable OGPhysicsTransformBlock)block forView:(UIView *)view {
    ELEM_FOR_VIEW(view);
    elem.physics.transformBlock = [block copy];
}

- (void)setContentTexture:(nullable id<MTLTexture>)texture forView:(UIView *)view {
    ELEM_FOR_VIEW(view);
    elem.contentTexture = texture;
}

- (void)setLuminanceBlock:(nullable OGLuminanceBlock)block forView:(UIView *)view {
    ELEM_FOR_VIEW(view);
    elem.physics.luminanceBlock = [block copy];
}

#undef ELEM_FOR_VIEW

- (void)_tick:(CADisplayLink *)link {
    if (_elements.empty()) return;
    @autoreleasepool {
        CFTimeInterval now = CACurrentMediaTime();
        float dt = _previousTimestamp > 0 ? (float)(now - _previousTimestamp) : 0.016f;
        dt = fmaxf(0.001f, fminf(0.05f, dt));
        _previousTimestamp = now;
        [self _renderFrame:dt];
    }
}

- (void)_flushPendingRemovals {
    for (const void *key : _pendingRemovals) {
        _elements.erase(key);
    }
    _pendingRemovals.clear();
}

- (void)_renderFrame:(float)dt {
    [self _flushPendingRemovals];

    for (auto &pair : _elements) {
        updatePhysics(pair.second.physics, pair.second.config, dt);
    }

    for (auto &g : _groupVec) {
        g.views.clear(); g.configs.clear();
        g.cachedRects.clear(); g.cutoffs.clear();
        g.source = nil;
    }
    size_t groupCount = 0;

    for (UIView *view in _viewSet) {
        if (![self _isEffectivelyVisible:view]) continue;
        if (view.bounds.size.width <= 0 || view.bounds.size.height <= 0) continue;

        const void *key = (__bridge const void *)view;
        auto it = _elements.find(key);
        if (it == _elements.end()) continue;
        GlassElement &elem = it->second;
        if (!elem.metalLayer) continue;

        UIView *source = elem.sourceView;
        if (!source) {
            UIWindow *window = view.window;
            source = window.rootViewController.view ?: (UIView *)window;
        }
        if (!source) continue;

        const void *sourceKey = (__bridge const void *)source;
        SourceGroup *found = nullptr;
        for (size_t gi = 0; gi < groupCount; gi++) {
            if ((__bridge const void *)_groupVec[gi].source == sourceKey) {
                found = &_groupVec[gi]; break;
            }
        }
        if (!found) {
            if (groupCount >= _groupVec.size()) _groupVec.emplace_back();
            found = &_groupVec[groupCount];
            found->source = source;
            groupCount++;
        }
        found->views.push_back(view);
        found->configs.push_back(&elem);
    }

    if (groupCount == 0) return;

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    if (!commandBuffer) return;
    [_captureEngine advanceFrame];

    CGFloat scale = _screenScale;
    id<CAMetalDrawable> pendingDrawables[32];
    int drawableCount = 0;

    for (size_t gi = 0; gi < groupCount; gi++) {
        SourceGroup &group = _groupVec[gi];
        UIView *source = group.source;
        size_t count = group.views.size();
        [source layoutIfNeeded];

        group.cachedRects.resize(count);
        [_scratchGlassLayers removeAllObjects];
        CGRect unionRect = CGRectNull;

        for (size_t i = 0; i < count; i++) {
            UIView *view = group.views[i];
            group.cachedRects[i] = [view convertRect:view.bounds toView:source];
            CALayer *exclusion = group.configs[i]->exclusionLayer ?: view.layer;
            [_scratchGlassLayers addObject:exclusion];

            CGFloat blur = (CGFloat)group.configs[i]->config.blurRadius;
            CGFloat extra = blur + 30;
            CGRect cr = CGRectInset(group.cachedRects[i], -extra, -extra);
            cr = CGRectIntersection(cr, source.bounds);
            if (cr.size.width > 0 && cr.size.height > 0) {
                unionRect = CGRectIsNull(unionRect) ? cr : CGRectUnion(unionRect, cr);
            }
        }

        if (CGRectIsNull(unionRect)) continue;

        [_captureEngine traverseLayer:source.layer
                       allGlassLayers:_scratchGlassLayers
                               inRect:unionRect];

        float s = (float)scale;

        group.cutoffs.resize(count);
        for (size_t i = 0; i < count; i++) {
            CALayer *exclusion = group.configs[i]->exclusionLayer ?: group.views[i].layer;
            group.cutoffs[i] = [_captureEngine cutoffForGlassLayer:exclusion];
        }

        std::vector<uint32_t> sortedCutoffs(group.cutoffs.begin(), group.cutoffs.end());
        std::sort(sortedCutoffs.begin(), sortedCutoffs.end());
        sortedCutoffs.erase(std::unique(sortedCutoffs.begin(), sortedCutoffs.end()), sortedCutoffs.end());

        uint32_t prevCutoff = 0;
        for (uint32_t cutoff : sortedCutoffs) {
            if (![_captureEngine prepareForCutoff:cutoff fromIndex:prevCutoff scale:scale]) {
                prevCutoff = cutoff; continue;
            }

            for (size_t j = 0; j < count; j++) {
                if (group.cutoffs[j] != cutoff) continue;

                UIView *view = group.views[j];
                GlassElement &elem = *group.configs[j];
                OGGlassConfig c = elem.config;
                OGPhysicsState &phys = elem.physics;
                CAMetalLayer *ml = elem.metalLayer;

                id<CAMetalDrawable> drawable = [ml nextDrawable];
                if (!drawable) continue;

                int readIdx = elem.avgLumIndex;
                int writeIdx = (readIdx + 1) % kAvgLumBufferCount;
                if (elem.avgLumBuffers[readIdx]) {
                    float gpuLum = *(float *)elem.avgLumBuffers[readIdx].contents;
                    phys.lastLuminance = fmaxf(0.0f, fminf(1.0f, gpuLum));
                }
                elem.avgLumIndex = writeIdx;

                CGRect logicalRect = group.cachedRects[j];
                CGFloat blur = (CGFloat)c.blurRadius;
                CGRect captureRect = CGRectInset(logicalRect, -(blur + 30), -(blur + 30));
                captureRect = CGRectIntersection(captureRect, source.bounds);
                if (captureRect.size.width <= 0 || captureRect.size.height <= 0) continue;

                id<MTLTexture> texture = [_captureEngine renderCompositeInRect:captureRect
                                                                         scale:scale
                                                                 commandBuffer:commandBuffer];
                if (!texture) continue;

                CGSize logicalSize = logicalRect.size;
                CGSize renderSize = ml.bounds.size;
                float padding = (float)((renderSize.width - logicalSize.width) / 2.0);
                float offX = (float)(logicalRect.origin.x - captureRect.origin.x);
                float offY = (float)(logicalRect.origin.y - captureRect.origin.y);
                float maxR = (float)(fmin(logicalSize.width, logicalSize.height) / 2.0);
                bool hasPhy = (c.physicsMode != OGPhysicsModeNone);

                GlassUniforms uniforms;
                uniforms.size = simd_make_float2((float)logicalSize.width * s, (float)logicalSize.height * s);
                uniforms.renderSize = simd_make_float2((float)renderSize.width * s, (float)renderSize.height * s);
                uniforms.offset = simd_make_float2(offX * s, offY * s);
                uniforms.backgroundSize = simd_make_float2((float)texture.width, (float)texture.height);
                uniforms.padding = padding * s;
                uniforms.cornerRadius = fminf(c.cornerRadius, maxR) * s;
                uniforms.blurRadius = c.blurRadius * s;
                uniforms.refractionStrength = c.refractionStrength;
                uniforms.chromeStrength = c.chromeStrength;
                uniforms.edgeBandMultiplier = c.edgeBandMultiplier;
                uniforms.zoom = c.zoom;
                uniforms.edgeShadowStrength = c.edgeShadowStrength;
                uniforms.overallShadowStrength = c.overallShadowStrength;
                uniforms.glassTintStrength = c.glassTintStrength;
                phys.isDarkMode = (view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
                uniforms.isDarkMode = phys.isDarkMode ? 1.0f : 0.0f;
                uniforms.physScale = hasPhy ? phys.scale : 1.0f;
                uniforms.physOpacity = hasPhy ? phys.opacity : 1.0f;
                uniforms.physStretchX = hasPhy ? phys.stretchX : 1.0f;
                uniforms.physStretchY = hasPhy ? phys.stretchY : 1.0f;
                uniforms.physRotation = hasPhy ? phys.rotation : 0.0f;
                uniforms.physOffsetX = hasPhy ? phys.offsetX * s : 0.0f;
                uniforms.physOffsetY = hasPhy ? phys.offsetY * s : 0.0f;
                uniforms.hasContent = elem.contentTexture ? 1.0f : 0.0f;
                uniforms.tintRegime = phys.tintRegime;

                {
                    LumUniforms lumU;
                    lumU.offset = uniforms.offset;
                    lumU.size = uniforms.size;
                    lumU.backgroundSize = uniforms.backgroundSize;
                    id<MTLComputeCommandEncoder> compEnc = [commandBuffer computeCommandEncoder];
                    [compEnc setComputePipelineState:_lumComputePipeline];
                    [compEnc setTexture:texture atIndex:0];
                    [compEnc setBytes:&lumU length:sizeof(LumUniforms) atIndex:0];
                    [compEnc setBuffer:elem.avgLumBuffers[writeIdx] offset:0 atIndex:1];
                    [compEnc dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                    [compEnc endEncoding];
                }

                MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor new];
                rpd.colorAttachments[0].texture = drawable.texture;
                rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
                rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
                rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

                id<MTLRenderCommandEncoder> enc = [commandBuffer renderCommandEncoderWithDescriptor:rpd];
                if (!enc) continue;
                [enc setRenderPipelineState:_glassPipeline];
                [enc setFragmentTexture:texture atIndex:0];
                if (elem.contentTexture) {
                    [enc setFragmentTexture:elem.contentTexture atIndex:1];
                }
                [enc setFragmentBytes:&uniforms length:sizeof(GlassUniforms) atIndex:0];
                [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                [enc endEncoding];

                if (drawableCount < 32) pendingDrawables[drawableCount++] = drawable;

                if (hasPhy && phys.transformBlock) {
                    phys.transformBlock(phys.scale, phys.opacity,
                                        phys.stretchX, phys.stretchY,
                                        phys.rotation, phys.offsetX, phys.offsetY);
                }
                if (phys.luminanceBlock) {
                    phys.luminanceBlock(phys.tintRegime);
                }
            }
            prevCutoff = cutoff;
        }
    }

    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
    for (int i = 0; i < drawableCount; i++) [pendingDrawables[i] present];

    if (_groupVec.size() > groupCount * 2 + 4) _groupVec.resize(groupCount);
}


- (BOOL)_isEffectivelyVisible:(UIView *)view {
    UIWindow *window = view.window;
    if (!window) return NO;
    UIView *v = view;
    while (v) {
        if (v.isHidden || v.alpha < 0.001) return NO;
        v = v.superview;
    }
    CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
    return !CGRectIsEmpty(frameInWindow) && CGRectIntersectsRect(frameInWindow, window.bounds);
}

@end
