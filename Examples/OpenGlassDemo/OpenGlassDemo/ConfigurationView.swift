import OpenGlass
import SwiftUI

struct ConfigurationView: View {
    @Binding var configuration: GlassConfiguration
    @Binding var glassSize: CGSize
    @Environment(\.presentationMode) private var presentationMode

    private let tintColors: [(String, GlassTintColor?)] = [
        ("None", nil),
        ("Blue", GlassTintColor(red: 0.0, green: 0.5, blue: 1.0)),
        ("Red", GlassTintColor(red: 1.0, green: 0.3, blue: 0.3)),
        ("Green", GlassTintColor(red: 0.3, green: 0.8, blue: 0.4)),
        ("Purple", GlassTintColor(red: 0.7, green: 0.3, blue: 0.9)),
        ("Orange", GlassTintColor(red: 1.0, green: 0.6, blue: 0.2)),
        ("Cyan", GlassTintColor(red: 0.2, green: 0.9, blue: 0.9)),
        ("Pink", GlassTintColor(red: 1.0, green: 0.4, blue: 0.6)),
    ]

    @State private var horizontalMin: CGFloat = 80
    @State private var horizontalMax: CGFloat = 320
    @State private var verticalMin: CGFloat = 150
    @State private var verticalMax: CGFloat = 650
    @State private var rectMinX: CGFloat = 60
    @State private var rectMaxX: CGFloat = 340
    @State private var rectMinY: CGFloat = 200
    @State private var rectMaxY: CGFloat = 600

    @State private var showVelocityStretch = false
    @State private var showSprings = false
    @State private var showRotation = false
    @State private var showAnchored = false
    @State private var showPressFeedback = false
    @State private var showRefraction = false
    @State private var showBlur = false
    @State private var showLighting = false

    private var selectedPhysicsMode: Int {
        switch configuration.physics.bounds {
        case .none: 0
        case .anchored: 1
        case .horizontal: 2
        case .vertical: 3
        case .rect: 4
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Shape")) {
                    SliderRow(title: "Width", value: $glassSize.width, range: 80 ... 350)
                    SliderRow(title: "Height", value: $glassSize.height, range: 40 ... 350)
                    SliderRow(title: "Corner Radius", value: $configuration.cornerRadius, range: 0 ... 100)
                }

                Section(header: Text("Physics Mode")) {
                    Picker("Mode", selection: Binding(
                        get: { selectedPhysicsMode },
                        set: { updatePhysicsBounds($0) },
                    )) {
                        Text("Free").tag(0)
                        Text("Anchor").tag(1)
                        Text("H").tag(2)
                        Text("V").tag(3)
                        Text("Rect").tag(4)
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text(physicsDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if selectedPhysicsMode == 2 {
                    Section(header: Text("Horizontal Bounds")) {
                        SliderRow(title: "Min X", value: $horizontalMin, range: 20 ... 200)
                        SliderRow(title: "Max X", value: $horizontalMax, range: 200 ... 380)
                    }
                    .onChange(of: horizontalMin) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                    .onChange(of: horizontalMax) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                }

                if selectedPhysicsMode == 3 {
                    Section(header: Text("Vertical Bounds")) {
                        SliderRow(title: "Min Y", value: $verticalMin, range: 80 ... 300)
                        SliderRow(title: "Max Y", value: $verticalMax, range: 400 ... 800)
                    }
                    .onChange(of: verticalMin) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                    .onChange(of: verticalMax) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                }

                if selectedPhysicsMode == 4 {
                    Section(header: Text("Rect Bounds")) {
                        SliderRow(title: "Min X", value: $rectMinX, range: 20 ... 150)
                        SliderRow(title: "Max X", value: $rectMaxX, range: 250 ... 400)
                        SliderRow(title: "Min Y", value: $rectMinY, range: 100 ... 300)
                        SliderRow(title: "Max Y", value: $rectMaxY, range: 500 ... 750)
                    }
                    .onChange(of: rectMinX) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                    .onChange(of: rectMaxX) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                    .onChange(of: rectMinY) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                    .onChange(of: rectMaxY) { _ in updatePhysicsBounds(selectedPhysicsMode) }
                }

                Section {
                    DisclosureGroup("Velocity Stretch", isExpanded: $showVelocityStretch) {
                        SliderRow(title: "Sensitivity", value: $configuration.physics.velocityStretchSensitivity, range: 0.0005 ... 0.003)
                        SliderRow(title: "Max Stretch", value: $configuration.physics.maxStretchAlongVelocity, range: 1.0 ... 1.5)
                        SliderRow(title: "Min Compress", value: $configuration.physics.minStretchPerpendicular, range: 0.7 ... 1.0)
                    }
                }

                Section {
                    DisclosureGroup("Springs", isExpanded: $showSprings) {
                        SliderRow(title: "Stretch Stiffness", value: $configuration.physics.stretchSpringStiffness, range: 50 ... 400)
                        SliderRow(title: "Stretch Damping", value: $configuration.physics.stretchSpringDamping, range: 5 ... 30)
                        SliderRow(title: "Rotation Stiffness", value: $configuration.physics.rotationSpringStiffness, range: 50 ... 400)
                        SliderRow(title: "Rotation Damping", value: $configuration.physics.rotationSpringDamping, range: 5 ... 30)
                    }
                }

                Section {
                    DisclosureGroup("Rotation", isExpanded: $showRotation) {
                        SliderRow(title: "Sensitivity", value: $configuration.physics.velocityRotationSensitivity, range: 0.00001 ... 0.0002)
                        SliderRow(title: "Max Rotation", value: $configuration.physics.maxRotation, range: 0.05 ... 0.4)
                    }
                }

                Section {
                    DisclosureGroup("Anchored Mode", isExpanded: $showAnchored) {
                        SliderRow(title: "Stretch Sensitivity", value: $configuration.physics.anchoredStretchSensitivity, range: 0.001 ... 0.01)
                        SliderRow(title: "Max Stretch", value: $configuration.physics.anchoredMaxStretch, range: 1.1 ... 1.5)
                        SliderRow(title: "Max Offset", value: $configuration.physics.anchoredMaxOffset, range: 5 ... 30)
                        SliderRow(title: "Offset Stiffness", value: $configuration.physics.anchoredOffsetStiffness, range: 0.003 ... 0.02)
                    }
                }

                Section {
                    DisclosureGroup("Press Feedback", isExpanded: $showPressFeedback) {
                        SliderRow(title: "Pressed Scale", value: $configuration.physics.pressedScale, range: 0.9 ... 1.0)
                        SliderRow(title: "Pressed Opacity", value: $configuration.physics.pressedOpacity, range: 0.7 ... 1.0)
                    }
                }

                Section {
                    DisclosureGroup("Refraction & Chrome", isExpanded: $showRefraction) {
                        SliderRow(title: "Refraction", value: $configuration.refractionStrength, range: 0 ... 1)
                        SliderRow(title: "Edge Band", value: $configuration.edgeBandMultiplier, range: 0.1 ... 0.5)
                        SliderRow(title: "Chrome", value: $configuration.chromeStrength, range: 0 ... 10)
                    }
                }

                Section {
                    DisclosureGroup("Blur & Zoom", isExpanded: $showBlur) {
                        SliderRow(title: "Blur", value: $configuration.blurRadius, range: 0 ... 50)
                        SliderRow(title: "Glass Tint", value: $configuration.glassTintStrength, range: 0 ... 0.5)
                        SliderRow(title: "Zoom", value: $configuration.zoom, range: 0.5 ... 1.5)
                    }
                }

                Section {
                    DisclosureGroup("Lighting", isExpanded: $showLighting) {
                        SliderRow(title: "Top Highlight", value: $configuration.topHighlightStrength, range: 0 ... 0.15)
                        SliderRow(title: "Edge Shadow", value: $configuration.edgeShadowStrength, range: 0 ... 0.15)
                        SliderRow(title: "Overall Shadow", value: $configuration.overallShadowStrength, range: 0 ... 0.1)
                    }
                }

                Section(header: Text("Color Tint")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.subheadline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tintColors, id: \.0) { name, color in
                                    TintColorButton(
                                        name: name,
                                        color: color,
                                        isSelected: isTintColorSelected(color),
                                        action: { configuration.tintColor = color },
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Blend Mode")
                            .font(.subheadline)
                        Picker("Mode", selection: $configuration.tintMode) {
                            ForEach(OpenGlassTintMode.allCases, id: \.self) { mode in
                                Text(mode.description).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(.vertical, 4)

                    SliderRow(title: "Intensity", value: $configuration.tintIntensity, range: 0 ... 1)
                }

                Section(header: Text("Presets")) {
                    Button("Pill") { applyPreset(.pill) }
                    Button("Card") { applyPreset(.card) }
                    Button("Orb") { applyPreset(.orb) }
                    Button("Panel") { applyPreset(.panel) }
                    Button("Lens") { applyPreset(.lens) }
                }

                Section {
                    Button(action: {
                        configuration = GlassConfiguration()
                        glassSize = CGSize(width: 200, height: 200)
                    }) {
                        Text("Reset All")
                            .foregroundColor(.red)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func applyPreset(_ preset: GlassConfiguration.Preset) {
        withAnimation(.easeInOut(duration: 0.3)) {
            configuration = GlassConfiguration.preset(preset)
            glassSize = GlassConfiguration.presetSize(preset)
        }
    }

    private func isTintColorSelected(_ color: GlassTintColor?) -> Bool {
        guard let current = configuration.tintColor, let check = color else {
            return configuration.tintColor == nil && color == nil
        }
        return abs(current.red - check.red) < 0.01 &&
            abs(current.green - check.green) < 0.01 &&
            abs(current.blue - check.blue) < 0.01
    }

    private var physicsDescription: String {
        switch selectedPhysicsMode {
        case 0:
            "Drag the glass around. It will squash-stretch based on velocity and tilt into movement."
        case 1:
            "Touch and drag on the glass. It stretches toward your finger but stays in place."
        case 2:
            "Drag horizontally within bounds. Stretches against edges and when dragging vertically."
        case 3:
            "Drag vertically within bounds. Stretches against edges and when dragging horizontally."
        case 4:
            "Move freely inside the rectangle. Stretches against any edge when you hit the boundary."
        default:
            ""
        }
    }

    private func updatePhysicsBounds(_ mode: Int) {
        switch mode {
        case 0:
            configuration.physics.bounds = .none
        case 1:
            configuration.physics.bounds = .anchored
        case 2:
            configuration.physics.bounds = .horizontal(min: horizontalMin, max: horizontalMax)
        case 3:
            configuration.physics.bounds = .vertical(min: verticalMin, max: verticalMax)
        case 4:
            configuration.physics.bounds = .rect(CGRect(x: rectMinX, y: rectMinY, width: rectMaxX - rectMinX, height: rectMaxY - rectMinY))
        default:
            break
        }
    }
}

struct SliderRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(formatValue(Double(value)))
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            Slider(value: $value, in: range)
        }
        .padding(.vertical, 4)
    }

    private func formatValue(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue < 0.001 {
            return String(format: "%.5f", value)
        } else if absValue < 0.01 {
            return String(format: "%.4f", value)
        } else if absValue < 0.1 {
            return String(format: "%.3f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}
