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
            NumberField("Threshold", value: field(\.threshold))
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
                "ABS, traction/stability and brake lights need no script: pick the channel the logger "
                    + "records the event on and the level that means \"active\"."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
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
            Toggle("Previous lap", isOn: field(\.showPrevious))
            Toggle("Current lap", isOn: field(\.showCurrent))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals), in: 1...3)
        }
        Section("Deltas to the best lap") {
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
                "Both compare with the best completed lap at the same distance into the lap "
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
