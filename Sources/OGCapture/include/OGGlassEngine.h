#ifndef OGGlassEngine_h
#define OGGlassEngine_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "OGGlassConfig.h"

@class UIView;

NS_ASSUME_NONNULL_BEGIN

typedef void (^OGPhysicsTransformBlock)(float scale, float opacity,
                                         float stretchX, float stretchY,
                                         float rotation,
                                         float offsetX, float offsetY);

typedef void (^OGLuminanceBlock)(float luminance);

NS_SWIFT_UI_ACTOR
@interface OGGlassEngine : NSObject

+ (void)setupWithDevice:(id<MTLDevice>)device
          glassPipeline:(id<MTLRenderPipelineState>)glassPipeline
     compositorPipeline:(id<MTLRenderPipelineState>)compositorPipeline
      maskApplyPipeline:(id<MTLRenderPipelineState>)maskApplyPipeline
    lumComputePipeline:(id<MTLComputePipelineState>)lumComputePipeline;

@property (class, readonly, nullable) OGGlassEngine *shared;
@property (nonatomic, readonly) id<MTLDevice> device;

- (void)registerView:(UIView *)view;
- (void)unregisterView:(UIView *)view;
- (void)setConfig:(OGGlassConfig)config forView:(UIView *)view;
- (void)setSourceView:(nullable UIView *)sourceView forView:(UIView *)view;
- (void)setExclusionLayer:(nullable CALayer *)layer forView:(UIView *)view;
- (void)setMetalLayer:(CAMetalLayer *)layer forView:(UIView *)view;

- (void)setTouchActive:(BOOL)active forView:(UIView *)view position:(CGPoint)position;
- (void)setDragVelocity:(CGPoint)velocity forView:(UIView *)view;
- (void)setPhysicsTransformBlock:(nullable OGPhysicsTransformBlock)block forView:(UIView *)view;
- (void)setContentTexture:(nullable id<MTLTexture>)texture forView:(UIView *)view;
- (void)setLuminanceBlock:(nullable OGLuminanceBlock)block forView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END

#endif
