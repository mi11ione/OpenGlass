#ifndef OGCaptureEngine_h
#define OGCaptureEngine_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface OGCaptureEngine : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, nullable) id<MTLRenderPipelineState> compositorPipeline;
@property (nonatomic, strong, nullable) id<MTLRenderPipelineState> maskApplyPipeline;

- (void)advanceFrame;

- (void)traverseLayer:(CALayer *)rootLayer
       allGlassLayers:(NSSet<CALayer *> *)allGlass
               inRect:(CGRect)unionRect;

- (uint32_t)cutoffForGlassLayer:(CALayer *)glassLayer;

- (BOOL)prepareForCutoff:(uint32_t)cutoff fromIndex:(uint32_t)fromIndex scale:(CGFloat)scale;

- (nullable id<MTLTexture>)renderCompositeInRect:(CGRect)rect
                                           scale:(CGFloat)scale
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

- (void)flush;

@end

NS_ASSUME_NONNULL_END

#endif
