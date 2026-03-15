#import "OGLayerTraversal.h"
#import <UIKit/UIView.h>
#import <objc/runtime.h>

static std::unordered_map<Class, bool> sDrawOverrideCache;

static bool delegateHasCustomDrawing(id delegate) {
    if (!delegate) return false;

    Class cls = object_getClass(delegate);

    auto it = sDrawOverrideCache.find(cls);
    if (it != sDrawOverrideCache.end()) return it->second;

    bool draws;
    if ([delegate isKindOfClass:[UIView class]]) {
        static IMP sBaseDrawRect = class_getMethodImplementation(
            [UIView class], @selector(drawRect:));
        static IMP sBaseDrawLayer = class_getMethodImplementation(
            [UIView class], @selector(drawLayer:inContext:));

        IMP actualDrawRect = class_getMethodImplementation(cls, @selector(drawRect:));
        IMP actualDrawLayer = class_getMethodImplementation(cls, @selector(drawLayer:inContext:));

        draws = (actualDrawRect != sBaseDrawRect) || (actualDrawLayer != sBaseDrawLayer);
    } else {
        draws = [delegate respondsToSelector:@selector(drawLayer:inContext:)];
    }

    sDrawOverrideCache[cls] = draws;
    return draws;
}

static bool layerHasFallbackContent(CALayer *layer, id contents) {
    if (contents) return true;

    if ([layer isKindOfClass:[CAShapeLayer class]])
        return ((CAShapeLayer *)layer).path != nil;

    if ([layer isKindOfClass:[CATextLayer class]])
        return ((CATextLayer *)layer).string != nil;

    if ([layer isKindOfClass:[CAGradientLayer class]])
        return ((CAGradientLayer *)layer).colors.count > 0;

    return delegateHasCustomDrawing(layer.delegate);
}

static CGAffineTransform projectTransform3DToAffine(CATransform3D m) {
    CGFloat w0 = m.m44;
    if (fabs(w0) < 1e-6) return CGAffineTransformIdentity;

    CGFloat invW0  = 1.0 / w0;
    CGFloat invW02 = invW0 * invW0;

    return CGAffineTransformMake(
        (m.m11 * w0 - m.m41 * m.m14) * invW02,
        (m.m12 * w0 - m.m42 * m.m14) * invW02,
        (m.m21 * w0 - m.m41 * m.m24) * invW02,
        (m.m22 * w0 - m.m42 * m.m24) * invW02,
        m.m41 * invW0,
        m.m42 * invW0
    );
}

static inline CALayer *pres(CALayer *layer) {
    return layer.presentationLayer ?: layer;
}

static CGAffineTransform sublayerTransformAffine(CALayer *layer) {
    CALayer *p = pres(layer);
    CATransform3D st = p.sublayerTransform;
    if (CATransform3DIsIdentity(st)) return CGAffineTransformIdentity;

    CGAffineTransform st2d = CATransform3DIsAffine(st)
        ? CATransform3DGetAffineTransform(st)
        : projectTransform3DToAffine(st);

    CGRect b = p.bounds;
    CGPoint a = p.anchorPoint;
    CGFloat ax = b.origin.x + b.size.width * a.x;
    CGFloat ay = b.origin.y + b.size.height * a.y;

    return CGAffineTransformConcat(
        CGAffineTransformMakeTranslation(-ax, -ay),
        CGAffineTransformConcat(st2d, CGAffineTransformMakeTranslation(ax, ay))
    );
}

static NSArray<CALayer *> *sortedSublayers(CALayer *layer) {
    NSArray<CALayer *> *subs = layer.sublayers;
    if (subs.count <= 1) return subs;

    BOOL needsSort = NO;
    for (CALayer *sub in subs) {
        if (pres(sub).zPosition != 0.0) {
            needsSort = YES;
            break;
        }
    }
    if (!needsSort) return subs;

    return [subs sortedArrayUsingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
        CGFloat az = pres(a).zPosition, bz = pres(b).zPosition;
        if (az < bz) return NSOrderedAscending;
        if (az > bz) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

static void emitLayer(
    CALayer *layer,
    CGAffineTransform worldTransform,
    CGRect worldBounds,
    float opacity,
    CGRect clipRect,
    std::vector<OGRenderItem> &outItems,
    std::vector<OGGradientData> &outGradients,
    std::vector<OGGradientStop> &outStops
) {
    CALayer *pl = pres(layer);

    OGRenderItem item{};
    item.transform = worldTransform;
    item.bounds = pl.bounds;
    item.worldBounds = worldBounds;
    item.clipRect = clipRect;
    item.opacity = opacity;
    item.contentType = OGRenderItem::kNone;
    item.cgImage = nullptr;
    item.fallbackLayer = layer;
    item.bgColor = simd_make_float4(0, 0, 0, 0);
    item.contentsRect = pl.contentsRect;

    id contents = pl.contents;
    if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
        item.contentType = OGRenderItem::kCGImage;
        item.cgImage = (__bridge CGImageRef)contents;

        NSString *gravity = pl.contentsGravity;
        size_t imgW = CGImageGetWidth(item.cgImage);
        size_t imgH = CGImageGetHeight(item.cgImage);
        CGFloat bW = item.bounds.size.width;
        CGFloat bH = item.bounds.size.height;
        if (imgW > 0 && imgH > 0 && bW > 0 && bH > 0) {
            CGFloat imgAspect = (CGFloat)imgW / (CGFloat)imgH;
            CGFloat boundsAspect = bW / bH;
            if ([gravity isEqualToString:kCAGravityResizeAspectFill]) {
                CGRect cr = item.contentsRect;
                if (imgAspect > boundsAspect) {
                    CGFloat vis = boundsAspect / imgAspect;
                    cr.origin.x += cr.size.width * (1.0 - vis) * 0.5;
                    cr.size.width *= vis;
                } else {
                    CGFloat vis = imgAspect / boundsAspect;
                    cr.origin.y += cr.size.height * (1.0 - vis) * 0.5;
                    cr.size.height *= vis;
                }
                item.contentsRect = cr;
            } else if ([gravity isEqualToString:kCAGravityResizeAspect]) {
                CGRect b = item.bounds;
                if (imgAspect > boundsAspect) {
                    CGFloat h = bW / imgAspect;
                    b.origin.y += (bH - h) * 0.5;
                    b.size.height = h;
                } else {
                    CGFloat w = bH * imgAspect;
                    b.origin.x += (bW - w) * 0.5;
                    b.size.width = w;
                }
                item.bounds = b;
            }
        }
    } else if ([layer isKindOfClass:[CAGradientLayer class]]) {
        CAGradientLayer *grad = (CAGradientLayer *)pl;
        NSArray *colors = grad.colors;
        bool isLinear = !grad.type || [grad.type isEqualToString:kCAGradientLayerAxial];
        if (isLinear && colors.count > 0) {
            int count = (int)colors.count;
            item.contentType = OGRenderItem::kLinearGradient;
            item.gradientIndex = (uint32_t)outGradients.size();

            OGGradientData gd{};
            gd.stopOffset = (uint32_t)outStops.size();
            gd.stopCount = (uint16_t)count;
            NSArray<NSNumber *> *locations = grad.locations;
            for (int i = 0; i < count; i++) {
                CGColorRef c = (__bridge CGColorRef)colors[i];
                const CGFloat *comp = CGColorGetComponents(c);
                size_t nc = CGColorGetNumberOfComponents(c);
                float cr = 0, cg = 0, cb = 0, ca = 1;
                if (nc >= 4) {
                    cr = (float)comp[0]; cg = (float)comp[1];
                    cb = (float)comp[2]; ca = (float)comp[3];
                } else if (nc >= 2) {
                    cr = cg = cb = (float)comp[0]; ca = (float)comp[1];
                }
                float loc = (locations && i < (int)locations.count)
                    ? (float)locations[i].floatValue
                    : (count > 1 ? (float)i / (float)(count - 1) : 0.0f);
                outStops.push_back({ cr, cg, cb, ca, loc });
            }
            CGPoint sp = grad.startPoint, ep = grad.endPoint;
            gd.startPoint[0] = (float)sp.x; gd.startPoint[1] = (float)sp.y;
            gd.endPoint[0] = (float)ep.x;   gd.endPoint[1] = (float)ep.y;
            outGradients.push_back(gd);
            item.contentsRect = CGRectMake(0, 0, 1, 1);
        } else if (colors.count > 0) {
            item.contentType = OGRenderItem::kFallback;
            item.fallbackLayer = layer;
        }
    } else if (layerHasFallbackContent(layer, contents)) {
        item.contentType = OGRenderItem::kFallback;
        item.fallbackLayer = layer;
    }

    CGColorRef bgColor = pl.backgroundColor;
    if (bgColor) {
        size_t n = CGColorGetNumberOfComponents(bgColor);
        const CGFloat *c = CGColorGetComponents(bgColor);
        float r = 0, g = 0, b = 0, a = 0;
        if (n >= 4) {
            r = (float)c[0]; g = (float)c[1]; b = (float)c[2]; a = (float)c[3];
        } else if (n >= 2) {
            r = g = b = (float)c[0]; a = (float)c[1];
        }
        item.bgColor = simd_make_float4(r * a, g * a, b * a, a);
    }

    bool hasContent = (item.contentType != OGRenderItem::kNone) || (item.bgColor[3] > 0.001f);
    if (hasContent) {
        outItems.push_back(item);
    }
}

static void emitMaskBegin(
    CALayer *maskLayer,
    CGAffineTransform parentWorldTransform,
    CGRect worldBounds,
    CGRect clipRect,
    std::vector<OGRenderItem> &outItems
) {
    CALayer *mp = pres(maskLayer);
    CGRect maskBounds = mp.bounds;
    CGPoint maskPos = mp.position;
    CGPoint maskAnchor = mp.anchorPoint;
    CGFloat maskAx = maskBounds.origin.x + maskBounds.size.width * maskAnchor.x;
    CGFloat maskAy = maskBounds.origin.y + maskBounds.size.height * maskAnchor.y;

    CGAffineTransform mt = CGAffineTransformMakeTranslation(-maskAx, -maskAy);
    CATransform3D mt3d = mp.transform;
    CGAffineTransform mt2d = CATransform3DIsAffine(mt3d)
        ? CATransform3DGetAffineTransform(mt3d)
        : projectTransform3DToAffine(mt3d);
    mt = CGAffineTransformConcat(mt, mt2d);
    mt = CGAffineTransformConcat(mt, CGAffineTransformMakeTranslation(maskPos.x, maskPos.y));
    CGAffineTransform maskWorldTransform = CGAffineTransformConcat(mt, parentWorldTransform);

    OGRenderItem beginItem{};
    beginItem.contentType = OGRenderItem::kMaskGroupBegin;
    beginItem.worldBounds = worldBounds;
    beginItem.clipRect = clipRect;
    beginItem.opacity = 1.0f;
    beginItem.maskLayer = maskLayer;
    beginItem.maskTransform = maskWorldTransform;
    beginItem.maskBounds = maskBounds;
    outItems.push_back(beginItem);
}

static void emitMaskEnd(
    CGRect worldBounds,
    CGRect clipRect,
    float opacity,
    std::vector<OGRenderItem> &outItems
) {
    OGRenderItem endItem{};
    endItem.contentType = OGRenderItem::kMaskGroupEnd;
    endItem.worldBounds = worldBounds;
    endItem.clipRect = clipRect;
    endItem.opacity = opacity;
    outItems.push_back(endItem);
}

static void traverseShared(
    CALayer *layer,
    NSSet<CALayer *> *allGlassLayers,
    CGAffineTransform parentTransform,
    float parentOpacity,
    CGRect captureRect,
    CGRect parentClipRect,
    std::vector<OGRenderItem> &outItems,
    std::vector<OGGradientData> &outGradients,
    std::vector<OGGradientStop> &outStops,
    std::unordered_map<const void *, uint32_t> &outGlassCutoffs
) {
    if ([allGlassLayers containsObject:layer]) {
        outGlassCutoffs[(__bridge const void *)layer] = (uint32_t)outItems.size();
        return;
    }

    CALayer *pl = pres(layer);

    if (pl.isHidden || pl.opacity < 0.001) return;

    CGRect bounds = pl.bounds;
    CGPoint position = pl.position;
    CGPoint anchor = pl.anchorPoint;

    CGFloat anchorX = bounds.origin.x + bounds.size.width * anchor.x;
    CGFloat anchorY = bounds.origin.y + bounds.size.height * anchor.y;

    CGAffineTransform t = CGAffineTransformMakeTranslation(-anchorX, -anchorY);

    CATransform3D t3d = pl.transform;
    CGAffineTransform t2d = CATransform3DIsAffine(t3d)
        ? CATransform3DGetAffineTransform(t3d)
        : projectTransform3DToAffine(t3d);

    t = CGAffineTransformConcat(t, t2d);
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(position.x, position.y));

    CGAffineTransform worldTransform = CGAffineTransformConcat(t, parentTransform);
    float accOpacity = parentOpacity * (float)pl.opacity;

    CGRect worldBounds = CGRectApplyAffineTransform(bounds, worldTransform);
    if (!CGRectIntersectsRect(worldBounds, captureRect)) return;

    CGRect currentClip = parentClipRect;
    if (pl.masksToBounds) {
        currentClip = CGRectIntersection(currentClip, worldBounds);
        if (CGRectIsEmpty(currentClip)) return;
    }

    CALayer *maskLayer = layer.mask;
    bool hasMask = (maskLayer != nil && !pres(maskLayer).isHidden && pres(maskLayer).opacity >= 0.001);

    bool forceSubtreeCapture = false;
    if (!pl.shouldRasterize && !pl.contents && !pl.backgroundColor) {
        NSString *cls = NSStringFromClass([layer class]);
        if ([cls hasSuffix:@"DrawingLayer"]) {
            forceSubtreeCapture = true;
        }
    }

    if (pl.shouldRasterize || forceSubtreeCapture) {
        OGRenderItem item{};
        item.transform = worldTransform;
        item.bounds = bounds;
        item.worldBounds = worldBounds;
        item.clipRect = currentClip;
        item.opacity = accOpacity;
        item.contentType = OGRenderItem::kFallbackSubtree;
        item.fallbackLayer = layer;
        item.cgImage = nullptr;
        item.bgColor = simd_make_float4(0, 0, 0, 0);
        item.contentsRect = CGRectMake(0, 0, 1, 1);
        outItems.push_back(item);
    } else {
        if (hasMask) {
            emitMaskBegin(maskLayer, worldTransform, worldBounds, currentClip, outItems);
        }

        emitLayer(layer, worldTransform, worldBounds, accOpacity, currentClip, outItems, outGradients, outStops);

        NSArray<CALayer *> *sublayers = sortedSublayers(layer);
        CGAffineTransform childParent = worldTransform;
        CGAffineTransform st = sublayerTransformAffine(layer);
        if (!CGAffineTransformIsIdentity(st)) {
            childParent = CGAffineTransformConcat(st, worldTransform);
        }
        for (CALayer *sub in sublayers) {
            traverseShared(sub, allGlassLayers, childParent, accOpacity, captureRect, currentClip, outItems, outGradients, outStops, outGlassCutoffs);
        }

        if (hasMask) {
            emitMaskEnd(worldBounds, currentClip, accOpacity, outItems);
        }
    }
}

void OGTraverseLayerTreeShared(
    CALayer *rootLayer,
    NSSet<CALayer *> *allGlassLayers,
    CGRect captureRect,
    std::vector<OGRenderItem> &outItems,
    std::vector<OGGradientData> &outGradients,
    std::vector<OGGradientStop> &outStops,
    std::unordered_map<const void *, uint32_t> &outGlassCutoffs
) {
    outItems.clear();
    outItems.reserve(128);
    outGradients.clear();
    outStops.clear();
    outGlassCutoffs.clear();

    CALayer *rootPres = pres(rootLayer);

    if (rootPres.isHidden || rootPres.opacity < 0.001) return;

    if ([allGlassLayers containsObject:rootLayer]) {
        outGlassCutoffs[(__bridge const void *)rootLayer] = 0;
        return;
    }

    float rootOpacity = (float)rootPres.opacity;
    CGRect rootBounds = rootPres.bounds;

    CGRect rootClip = CGRectInfinite;
    if (rootPres.masksToBounds) {
        rootClip = rootBounds;
    }

    CALayer *rootMask = rootLayer.mask;
    bool rootHasMask = (rootMask != nil && !pres(rootMask).isHidden && pres(rootMask).opacity >= 0.001);

    if (rootHasMask) {
        emitMaskBegin(rootMask, CGAffineTransformIdentity, rootBounds, rootClip, outItems);
    }

    emitLayer(rootLayer, CGAffineTransformIdentity, rootBounds, rootOpacity, rootClip, outItems, outGradients, outStops);

    NSArray<CALayer *> *sublayers = sortedSublayers(rootLayer);
    CGAffineTransform rootChildTransform = sublayerTransformAffine(rootLayer);
    for (CALayer *sub in sublayers) {
        traverseShared(sub, allGlassLayers, rootChildTransform, rootOpacity, captureRect, rootClip, outItems, outGradients, outStops, outGlassCutoffs);
    }

    if (rootHasMask) {
        emitMaskEnd(rootBounds, rootClip, rootOpacity, outItems);
    }
}
