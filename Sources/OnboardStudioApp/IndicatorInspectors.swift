import ProjectModel
import SwiftUI

struct IndicatorInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: IndicatorParams

    var body: some View {
        Section("Indicator") {
            Picker("Symbol", selection: field(\.glyph)) {
                ForEach(IndicatorGlyph.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            TextField("Label", text: field(\.label))
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            Picker("On when", selection: field(\.condition)) {
                ForEach(IndicatorCondition.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NumberField("Threshold", value: field(\.threshold)).accessibilityIdentifier("indicator.threshold")
            if let summary, let low = summary.minValue, let high = summary.maxValue {
                HStack {
                    Text("In this file: \(fmt(low)) … \(fmt(high))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let suggested = params.suggestedThreshold(for: summary) {
                        Button("Suggest \(fmt(suggested))") { update { $0.threshold = suggested } }
                            .font(.caption).accessibilityIdentifier("indicator.suggest")
                    }
                }
            }
            NumberField("Hold on (s)", value: field(\.holdSeconds), fractionDigits: 0...2)
            NumberField("Flash (Hz, 0 = steady)", value: field(\.flashHertz), fractionDigits: 0...1)
        }
        Section("Look") {
            ColorPicker("Lit", selection: color(\.onColor))
            ColorPicker("Dim", selection: color(\.offColor))
            Toggle("Show dim symbol when off", isOn: field(\.showWhenOff))
            Toggle("Glow when lit", isOn: field(\.glow))
            Toggle("Black outline", isOn: field(\.outline))
            Text(
                "ABS, traction/stability and brake lights need no script: pick the channel your logger "
                    + "records the event on (names differ between loggers) and the level that means \"active\"."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What the loaded data says about the chosen channel.
    var summary: ChannelSummary? {
        editor.channelSummaries(for: object.inputID).first { $0.identifier == params.channel }
    }

    func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    func field<T>(_ keyPath: WritableKeyPath<IndicatorParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<IndicatorParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout IndicatorParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Indicator") { $0.kind = .indicator(new) }
    }
}

struct LapPanelInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: LapPanelParams

    var body: some View {
        Section("Timing Panel") {
            Toggle("Best lap", isOn: field(\.showBest))
            if params.showBest { TextField("Heading", text: field(\.bestLabel)) }
            Toggle("Previous lap", isOn: field(\.showPrevious))
            if params.showPrevious { TextField("Heading", text: field(\.previousLabel)) }
            Toggle("Current lap", isOn: field(\.showCurrent))
            if params.showCurrent { TextField("Heading", text: field(\.currentLabel)) }
            Toggle("Lap numbers", isOn: field(\.showLapNumbers))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals), in: 1...3)
        }
        Section("Deltas") {
            Picker("Compare with", selection: field(\.reference)) {
                ForEach(LapReference.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("Speed lane", isOn: field(\.showSpeedDelta))
            if params.showSpeedDelta {
                SpeedUnitPicker(selection: field(\.speedUnit))
                NumberField("Speed scale (± units)", value: field(\.speedDeltaRange))
            }
            Toggle("Time lane", isOn: field(\.showTimeDelta))
            if params.showTimeDelta {
                NumberField("Time scale (± s)", value: field(\.timeDeltaRange), fractionDigits: 0...2)
            }
            Text(
                "Both lanes compare with the chosen lap at the same distance into the lap "
                    + "(needs a distance channel; GPS files get one)."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("Look") {
            ColorPicker("Text", selection: color(\.textColor))
            ColorPicker("Labels", selection: color(\.labelColor))
            ColorPicker("Ahead", selection: color(\.aheadColor))
            ColorPicker("Behind", selection: color(\.behindColor))
            ColorPicker("Background", selection: color(\.backgroundColor), supportsOpacity: true)
            Toggle("Black outline", isOn: field(\.outline))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<LapPanelParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<LapPanelParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout LapPanelParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Timing Panel") { $0.kind = .lapPanel(new) }
    }
}

struct SteeringWheelInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: SteeringWheelParams

    var body: some View {
        Section("Steering Wheel") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            NumberField("Degrees per unit", value: field(\.degreesPerUnit))
                .help("1 for a channel in degrees, 57.3 for radians, the lock angle for a −1…1 channel")
            Toggle("Invert direction", isOn: field(\.invert))
            NumberField("Limit (°, 0 = none)", value: field(\.maxDegrees), fractionDigits: 0...0)
        }
        Section("Look") {
            ColorPicker("Rim", selection: color(\.rimColor), supportsOpacity: true)
            ColorPicker("Rim edge", selection: color(\.edgeColor), supportsOpacity: true)
            PercentSlider("Rim thickness", value: field(\.rimWidth), range: 0.04...0.4)
            ColorPicker("Marker", selection: color(\.markerColor), supportsOpacity: true)
            PercentSlider("Marker width", value: field(\.markerWidth), range: 0.01...0.15)
            Toggle("Spokes", isOn: field(\.showSpokes))
            if params.showSpokes { ColorPicker("Spokes", selection: color(\.spokeColor), supportsOpacity: true) }
            Text(
                "Make the object wide and let it hang below the frame so only the upper arc shows. "
                    + "The rim's colour carries its own transparency."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<SteeringWheelParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<SteeringWheelParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout SteeringWheelParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Steering Wheel") { $0.kind = .steeringWheel(new) }
    }
}

/// One knob for a more see-through dashboard: fades the whole overlay layer over the video.
struct OverlayOpacitySection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Section("Overlay") {
            PercentSlider(
                "Overlay opacity",
                value: Binding(
                    get: { editor.project.settings.overlayOpacity },
                    set: { value in editor.edit("Change Overlay Opacity") { $0.settings.overlayOpacity = value } }),
                range: 0.1...1)
            Text("Fades every gauge, map and readout together, on top of each object's own opacity.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
