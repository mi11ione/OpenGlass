# OpenGlass

<p align="center">
    <img src="https://img.shields.io/badge/iOS-13.0+-007AFF.svg" />
    <img src="https://img.shields.io/badge/Swift-6.2-F05138.svg" />
    <img src="https://img.shields.io/badge/License-MIT-lightgrey.svg" />
</p>

Liquid Glass that works on iOS 13+. Pure Metal shaders, no private APIs

<p align="center">
    <img src="Examples/sandbox.gif" alt="OpenGlass Demo" width="300">
</p>

## Overview

OpenGlass brings iOS 26's Liquid Glass aesthetic to apps targeting iOS 13 and later. The effect isn't just blur, it's optical behavior: distance-based refraction and chromatic aberration that trigger human perception of physical glass.

The library provides a drop-in SwiftUI modifier, spring physics with squash-stretch and rotation, liquid morphing containers where adjacent elements blend together, and color tinting with multiple blend modes. A single shared screen capture keeps performance optimal even with many glass views on screen.

The API mirrors Apple's iOS 26 Glass API with an "Open" prefix to avoid conflicts: `.glassEffect()` becomes `.openGlassEffect()`, `GlassEffectContainer` becomes `OpenGlassEffectContainer`, and so on. If you're familiar with the native API, you already know how to use OpenGlass.

## Installation

Add OpenGlass to your project using Swift Package Manager:

```
https://github.com/mi11ione/OpenGlass
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mi11ione/OpenGlass", from: "1.0.0")
]
```

Then import it:

```swift
import OpenGlass
```

## Basic Usage

Apply the glass effect to any SwiftUI view:

```swift
Text("Hello, Glass")
    .padding()
    .openGlassEffect()
```

The modifier captures what's behind the view and renders it with refraction, chromatic aberration, blur, and lighting, all in real-time via Metal shaders.

Three styles are available: `.regular` for standard glass with moderate blur and refraction, `.clear` for transparent glass with minimal blur, and `.identity` for no visual effect (useful for animating glass in or out).

```swift
Text("Regular").openGlassEffect(.regular)
Text("Clear").openGlassEffect(.clear)
```

## Presets

For common shapes, use built-in configuration presets:

```swift
let pillConfig = GlassConfiguration.preset(.pill)
let cardConfig = GlassConfiguration.preset(.card)
let orbConfig = GlassConfiguration.preset(.orb)
let panelConfig = GlassConfiguration.preset(.panel)
let lensConfig = GlassConfiguration.preset(.lens)
```

Each preset configures corner radius, blur, refraction, and lighting for its intended use case.

## Shapes

Apply glass to standard SwiftUI shapes:

```swift
Image(systemName: "star.fill")
    .openGlassEffect(in: Circle())

Image(systemName: "heart.fill")
    .openGlassEffect(in: RoundedRectangle(cornerRadius: 16))

Image(systemName: "bolt.fill")
    .openGlassEffect(in: Capsule())
```

For per-corner control, use `openCornerConfiguration`:

```swift
Text("Custom Corners")
    .openGlassEffect(openCornerConfiguration: .corners(
        topLeading: .fixed(32),
        topTrailing: .fixed(8),
        bottomLeading: .fixed(8),
        bottomTrailing: .fixed(32)
    ))
```

Concentric corners maintain visual alignment with a parent container by calculating radius as `containerRadius - inset`:

```swift
.corners(topLeading: .containerConcentric(minimum: 8), ...)
```

## Tinting

Add color to your glass with five blend modes:

```swift
Text("Blue Glass")
    .openGlassEffect(.regular.tint(.blue))

Text("Vibrant")
    .openGlassEffect(.regular.tint(.purple, mode: .screen, intensity: 0.8))
```

Available modes are `.multiply` (darkens), `.overlay` (balanced, default), `.screen` (lightens), `.colorDodge` (strong highlights), and `.softLight` (subtle, natural).

## Button Styles

```swift
Button("Glass Button") { }
    .buttonStyle(.openGlass)

Button("Clear Glass") { }
    .buttonStyle(.openGlass(.clear))

Button("Prominent") { }
    .buttonStyle(.openGlassProminent)
```

## Containers

`OpenGlassEffectContainer` creates liquid morphing effects where adjacent glass elements blend together using smooth minimum SDF functions:

<p align="center">
    <img src="Examples/container.gif" alt="Container morphing" width="300">
</p>

```swift
OpenGlassEffectContainer(spacing: 12) {
    HStack(spacing: -4) {
        ForEach(["A", "B", "C"], id: \.self) { letter in
            Text(letter)
                .frame(width: 60, height: 50)
                .openGlassEffect()
        }
    }
}
```

The `spacing` parameter controls the blend zone width, higher values create smoother transitions. Works with any layout including grids.

## Physics

OpenGlass includes spring-based physics for natural touch interactions.

**Anchored mode** stretches toward your finger but stays in place:

```swift
Text("Anchored")
    .openGlassEffect(.regular.anchored())
```

**Free drag** moves freely with velocity-based squash-stretch:

```swift
Text("Draggable")
    .openGlassEffect(.regular.freeDrag())
```

**Bounded movement** constrains to an axis or rectangle:

```swift
Text("Slide")
    .openGlassEffect(.regular.horizontalBounds(min: 50, max: 300))

Text("Bounded")
    .openGlassEffect(.regular.bounded(CGRect(x: 50, y: 100, width: 250, height: 400)))
```

For fine-tuning, pass a custom `OpenGlassPhysicsConfiguration` with parameters for velocity sensitivity, stretch limits, spring stiffness, damping, and pressed-state scale.

## UIKit

For UIKit projects, use `OpenGlassView` directly:

```swift
let glassView = OpenGlassView(configuration: .preset(.pill))
glassView.frame = CGRect(x: 100, y: 200, width: 200, height: 50)
parentView.addSubview(glassView)
```

For containers, use `OpenGlassContainerRenderView` and register children via `registerChild(id:view:contentView:cornerRadii:...)`.

## Demo App

Open `OpenGlass.xcworkspace` to run the demo app alongside the library source. It includes a sandbox for tweaking every parameter in real-time, a showcase of styles and configurations, and interactive container demonstrations.

## How It Works

The glass effect is achieved through a shared screen capture system that takes a single snapshot per frame distributed to all glass views, SDF-based shape rendering with per-corner radii, optical simulation via edge-distance refraction and chromatic aberration, `smin()` blending for liquid mercury-like container transitions, and damped harmonic oscillators for spring physics.

## License

MIT License. See [LICENSE](LICENSE) for details.
