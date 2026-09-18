import ProjectModel
import SwiftUI

/// Picture, chroma-key and audio sections for a video input.
struct VideoInputInspector: View {
    @Bindable var editor: EditorModel
    let input: Input
    let settings: VideoInputSettings

    var body: some View {
        Section("Picture") {
            Picker("Rotation", selection: field(\.rotation, name: "Rotate Picture")) {
                Text("0°").tag(0.0)
                Text("90°").tag(90.0)
                Text("180°").tag(180.0)
                Text("270°").tag(270.0)
            }
            Toggle("Mirror horizontally", isOn: field(\.mirror.horizontal, name: "Mirror Picture"))
            Toggle("Mirror vertically", isOn: field(\.mirror.vertical, name: "Mirror Picture"))
            PercentSlider("Crop top", value: field(\.crop.top, name: "Crop Picture"), range: 0...0.45)
            PercentSlider("Crop bottom", value: field(\.crop.bottom, name: "Crop Picture"), range: 0...0.45)
            PercentSlider("Crop left", value: field(\.crop.left, name: "Crop Picture"), range: 0...0.45)
            PercentSlider("Crop right", value: field(\.crop.right, name: "Crop Picture"), range: 0...0.45)
        }
        Section("Colour") {
            PercentSlider("Brightness", value: field(\.color.brightness, name: "Adjust Colour"), range: 0...2)
            PercentSlider("Contrast", value: field(\.color.contrast, name: "Adjust Colour"), range: 0...2)
            PercentSlider("Saturation", value: field(\.color.saturation, name: "Adjust Colour"), range: 0...2)
            Slider(value: field(\.color.hue, name: "Adjust Colour"), in: -180...180, step: 1) {
                Text("Hue \(Int(settings.color.hue))°")
            }
            PercentSlider("Sharpness", value: field(\.color.sharpness, name: "Adjust Colour"), range: 0...2)
            Button("Reset colour") { update("Reset Colour") { $0.color = .neutral } }.disabled(settings.color.isNeutral)
        }
        Section("Lens") {
            Picker("Unwrap", selection: field(\.lens.mode, name: "Change Lens")) {
                ForEach(LensMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if settings.lens.isActive {
                if settings.lens.mode == .fisheye {
                    Slider(value: field(\.lens.fov, name: "Change Lens FOV"), in: 100...250, step: 1) {
                        Text("Source FOV \(Int(settings.lens.fov))°")
                    }
                }
                Slider(value: field(\.lens.outputFov, name: "Change Lens Zoom"), in: 40...150, step: 1) {
                    Text("View FOV \(Int(settings.lens.outputFov))°")
                }
                Slider(value: field(\.lens.yaw, name: "Pan Lens"), in: -180...180, step: 1) {
                    Text("Yaw \(Int(settings.lens.yaw))°")
                }
                Slider(value: field(\.lens.pitch, name: "Tilt Lens"), in: -90...90, step: 1) {
                    Text("Pitch \(Int(settings.lens.pitch))°")
                }
                Slider(value: field(\.lens.roll, name: "Roll Lens"), in: -180...180, step: 1) {
                    Text("Roll \(Int(settings.lens.roll))°")
                }
                Button("Reset view") {
                    update("Reset Lens") { $0.lens = LensSettings(mode: $0.lens.mode, fov: $0.lens.fov) }
                }
                Text(
                    settings.lens.mode == .fisheye
                        ? "Straightens a fisheye picture; set the source FOV to the lens's horizontal field of view."
                        : "Shows a flat window into the 360° panorama; pan with yaw and pitch."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Chroma Key") {
            Toggle(
                "Make a colour transparent",
                isOn: Binding(
                    get: { settings.chromaKey != nil },
                    set: { on in update("Toggle Chroma Key") { $0.chromaKey = on ? ChromaKey() : nil } }))
            if let key = settings.chromaKey {
                ColorPicker(
                    "Key colour",
                    selection: Binding(
                        get: { Color(key.color) },
                        set: { color in update("Change Key Colour") { $0.chromaKey?.color = RGBAColor(color) } }),
                    supportsOpacity: false)
                PercentSlider(
                    "Tolerance",
                    value: Binding(
                        get: { key.tolerance },
                        set: { v in update("Change Key Tolerance") { $0.chromaKey?.tolerance = v } }), range: 0.02...1)
                PercentSlider(
                    "Softness",
                    value: Binding(
                        get: { key.softness },
                        set: { v in update("Change Key Softness") { $0.chromaKey?.softness = v } }), range: 0...0.5)
            }
        }
        Section("Audio") {
            Toggle("Include audio", isOn: field(\.includeAudio, name: "Toggle Audio"))
            if settings.includeAudio {
                Toggle("Mute", isOn: field(\.audio.isMuted, name: "Mute Audio"))
                PercentSlider("Volume", value: field(\.audio.volume, name: "Change Volume"), range: 0...2)
                Slider(value: field(\.audio.balance, name: "Change Balance"), in: -1...1) {
                    Text("Balance")
                } minimumValueLabel: {
                    Text("L")
                } maximumValueLabel: {
                    Text("R")
                }
                Picker("Channels", selection: field(\.audio.channels, name: "Change Channels")) {
                    Text("Stereo").tag(AudioChannelSelection.stereo)
                    Text("Mono").tag(AudioChannelSelection.mono)
                    Text("Left only").tag(AudioChannelSelection.left)
                    Text("Right only").tag(AudioChannelSelection.right)
                }
            }
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<VideoInputSettings, T>, name: String) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in update(name) { $0[keyPath: keyPath] = value } })
    }

    func update(_ name: String, _ change: (inout VideoInputSettings) -> Void) {
        var new = settings
        change(&new)
        editor.updateInput(input.id, name: name) { $0.kind = .video(new) }
    }
}

/// A slider showing its value as a percentage.
struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        Slider(value: $value, in: range) { Text("\(title) \(Int((value * 100).rounded()))%") }
    }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

extension RGBAColor {
    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(
            red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue),
            alpha: Double(resolved.opacity))
    }
}
