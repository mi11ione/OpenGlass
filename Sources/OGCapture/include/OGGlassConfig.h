#ifndef OGGlassConfig_h
#define OGGlassConfig_h

#include <stdint.h>

typedef enum : uint8_t {
    OGPhysicsModeNone = 0,
    OGPhysicsModePress = 1,
    OGPhysicsModeFree = 2,
    OGPhysicsModeAnchored = 3,
} OGPhysicsMode;

typedef struct {
    float cornerRadius;
    float refractionStrength;
    float edgeBandMultiplier;
    float chromeStrength;
    float blurRadius;
    float zoom;
    float edgeShadowStrength;
    float overallShadowStrength;
    float glassTintStrength;

    OGPhysicsMode physicsMode;
    float pressedScale;
    float pressedOpacity;
    float scaleStiffness;
    float scaleDamping;
    float opacityStiffness;
    float opacityDamping;
    float stretchStiffness;
    float stretchDamping;
    float rotationStiffness;
    float rotationDamping;
    float offsetStiffness;
    float offsetDamping;
    float velocityStretchSensitivity;
    float maxStretch;
    float minStretch;
    float velocityRotationSensitivity;
    float maxRotation;
    float anchoredStretchSensitivity;
    float anchoredMaxStretch;
    float anchoredMaxOffset;
    float anchoredOffsetStiffness;
} OGGlassConfig;

static inline OGGlassConfig OGGlassConfigDefault(void) {
    return (OGGlassConfig){
        .cornerRadius = 32.0f,
        .refractionStrength = 1.0f,
        .edgeBandMultiplier = 0.1f,
        .chromeStrength = 0.0f,
        .blurRadius = 2.4f,
        .zoom = 1.0f,
        .edgeShadowStrength = 0.01f,
        .overallShadowStrength = 0.02f,
        .glassTintStrength = 0.85f,

        .physicsMode = OGPhysicsModeNone,
        .pressedScale = 1.12f,
        .pressedOpacity = 1.0f,
        .scaleStiffness = 300.0f,
        .scaleDamping = 20.0f,
        .opacityStiffness = 400.0f,
        .opacityDamping = 25.0f,
        .stretchStiffness = 220.0f,
        .stretchDamping = 16.0f,
        .rotationStiffness = 200.0f,
        .rotationDamping = 14.0f,
        .offsetStiffness = 280.0f,
        .offsetDamping = 20.0f,
        .velocityStretchSensitivity = 0.0006f,
        .maxStretch = 1.12f,
        .minStretch = 0.92f,
        .velocityRotationSensitivity = 0.0f,
        .maxRotation = 0.0f,
        .anchoredStretchSensitivity = 0.0008f,
        .anchoredMaxStretch = 1.08f,
        .anchoredMaxOffset = 12.0f,
        .anchoredOffsetStiffness = 0.006f,
    };
}

#endif
