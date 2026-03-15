#ifndef OGLayerTraversal_h
#define OGLayerTraversal_h

#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
#include <vector>
#include <unordered_map>
#include "OGRenderItem.h"

void OGTraverseLayerTreeShared(
    CALayer * _Nonnull rootLayer,
    NSSet<CALayer *> * _Nonnull allGlassLayers,
    CGRect captureRect,
    std::vector<OGRenderItem> &outItems,
    std::vector<OGGradientData> &outGradients,
    std::vector<OGGradientStop> &outGradientStops,
    std::unordered_map<const void *, uint32_t> &outGlassCutoffs
);

#endif
#endif
