#ifndef OGCompositor_h
#define OGCompositor_h

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#ifdef __cplusplus
#include "OGRenderItem.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface OGCompositor : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                          pipelineState:(id<MTLRenderPipelineState>)pipelineState
                      maskApplyPipeline:(nullable id<MTLRenderPipelineState>)maskApplyPipeline;

- (void)beginFrame;
- (void)flush;

#ifdef __cplusplus
- (BOOL)prepareItems:(const OGRenderItem *)items
               count:(NSUInteger)count
           gradients:(const OGGradientData *)gradients
       gradientCount:(NSUInteger)gradientCount
       gradientStops:(const OGGradientStop *)stops
               scale:(CGFloat)scale
           fromIndex:(NSUInteger)startIndex;
#endif

- (void)renderIntoTexture:(id<MTLTexture>)texture
              captureRect:(CGRect)captureRect
                    scale:(CGFloat)scale
            commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
