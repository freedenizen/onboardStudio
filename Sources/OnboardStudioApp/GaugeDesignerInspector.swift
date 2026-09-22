import ProjectModel
import SwiftUI
import TelemetryKit

/// The Gauge Designer: every `GaugeParams` field, grouped the way RaceRender's designer is.
struct GaugeDesignerInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GaugeParams

    var body: some View {
        Section("Scale") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            TextField("Title", text: field(\.title))
            NumberField("Minimum", value: field(\.minValue))
            NumberField("Maximum", value: field(\.maxValue))
            NumberField("Major tick", value: field(\.majorTick))
            NumberField("Minor tick", value: field(\.minorTick))
            if ChannelRole(identifier: params.channel) == .speed {
                SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit))
            } else {
                TextField("Unit label", text: field(\.unitLabel))
                NumberField("Divide value by", value: field(\.valueDivisor))
            }
        }
        Section("Style") {
            Picker("Style", selection: field(\.style)) {
                Text("Needle").tag(GaugeStyle.needle)
                Text("Dual needle").tag(GaugeStyle.dualNeedle)
                Text("Filled arc").tag(GaugeStyle.arc)
            }
            NumberField("Sweep (°)", value: field(\.sweep))
            NumberField("Rotation (°)", value: field(\.rotation))
            Toggle("Counter-clockwise", isOn: field(\.counterClockwise))
            if params.style == .dualNeedle {
                OptionalChannelPicker(
                    editor: editor, title: "Second needle",
                    selection: Binding(
                        get: { params.secondChannel.isEmpty ? nil : params.secondChannel },
                        set: { v in update { $0.secondChannel = v ?? "" } }))
                ColorPicker("Second needle colour", selection: color(\.secondNeedleColor))
            }
            if params.style == .arc {
                PercentSlider("Arc width", value: field(\.arcWidth), range: 0.04...0.4)
                ColorPicker("Arc track", selection: color(\.arcTrackColor))
            }
            ColorPicker(params.style == .arc ? "Arc colour" : "Needle colour", selection: color(\.needleColor))
            ColorPicker("Text colour", selection: color(\.textColor))
        }
        if params.style != .arc {
            Section("Needle") {
                PercentSlider("Length", value: field(\.needle.length), range: 0.2...1)
                PercentSlider("Tail", value: field(\.needle.tailLength), range: 0...0.5)
                PercentSlider("Width", value: field(\.needle.width), range: 0.01...0.2)
                PercentSlider("Hub", value: field(\.needle.hubRadius), range: 0...0.3)
                Toggle("Tapered", isOn: field(\.needle.tapered))
                Slider(value: field(\.needle.smoothingSeconds), in: 0...2) {
                    Text(
                        params.needle.smoothingSeconds == 0
                            ? "Smoothing off" : "Smoothing \(String(format: "%.1f", params.needle.smoothingSeconds)) s")
                }
            }
        }
        Section("Ticks & Labels") {
            Toggle("Major ticks", isOn: field(\.ticks.showMajor))
            Toggle("Minor ticks", isOn: field(\.ticks.showMinor))
            Toggle("Labels", isOn: field(\.ticks.showLabels))
            PercentSlider("Major length", value: field(\.ticks.majorLength), range: 0.02...0.4)
            PercentSlider("Minor length", value: field(\.ticks.minorLength), range: 0.01...0.3)
            PercentSlider("Outer radius", value: field(\.ticks.outerRadius), range: 0.5...1)
            PercentSlider("Label radius", value: field(\.ticks.labelRadius), range: 0.3...1)
            PercentSlider("Label size", value: field(\.ticks.labelScale), range: 0.05...0.3)
            Stepper("Label decimals: \(params.ticks.labelDecimals)", value: field(\.ticks.labelDecimals), in: 0...3)
            Toggle("Declutter crowded labels", isOn: field(\.ticks.declutter))
        }
        Section("Zones") {
            ZoneListEditor(zones: field(\.zones), maximum: params.maxValue)
            Toggle("Paint band on face", isOn: field(\.zoneTargets.face))
            Toggle("Colour ticks and labels", isOn: field(\.zoneTargets.marks))
            Toggle(params.style == .arc ? "Colour arc" : "Colour needle", isOn: field(\.zoneTargets.needle))
            Toggle("Blend colours (gradient)", isOn: field(\.zoneTargets.gradient))
        }
        Section("Face") {
            Toggle("Show face", isOn: field(\.showFace))
            ColorPicker("Face colour", selection: color(\.faceColor))
            Picker("Face image", selection: field(\.faceImageInputID)) {
                Text("None").tag(InputID?.none)
                ForEach(editor.project.inputs.filter(\.kind.isImage)) { Text($0.label).tag(InputID?.some($0.id)) }
            }
            Button("Add Face Image…") { editor.addImageInput() }
        }
        Section("Readout") {
            Toggle("Show digital value", isOn: field(\.showValue))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals), in: 0...3)
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GaugeParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    func color(_ keyPath: WritableKeyPath<GaugeParams, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) },
            set: { value in update { $0[keyPath: keyPath] = RGBAColor(value) } })
    }

    func update(_ change: (inout GaugeParams) -> Void) {
        var new = params
        change(&new)
        let kind: DisplayObjectKind =
            switch object.kind {
            case .speedometer: .speedometer(new)
            case .tachometer: .tachometer(new)
            default: .gauge(new)
            }
        editor.updateObject(object.id, name: "Edit Gauge") { $0.kind = kind }
    }
}

/// Add/remove/edit coloured value ranges.
struct ZoneListEditor: View {
    @Binding var zones: [GaugeZone]
    let maximum: Double

    var body: some View {
        ForEach(zones) { zone in
            let index = zones.firstIndex { $0.id == zone.id } ?? 0
            HStack {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(zone.color) },
                        set: { c in if zones.indices.contains(index) { zones[index].color = RGBAColor(c) } })
                )
                .labelsHidden()
                TextField(
                    "From",
                    value: Binding(
                        get: { zone.from }, set: { v in if zones.indices.contains(index) { zones[index].from = v } }),
                    format: .number)
                Text("to")
                TextField(
                    "Max",
                    value: Binding(
                        get: { zone.to }, set: { v in if zones.indices.contains(index) { zones[index].to = v } }),
                    format: .number, prompt: Text("max"))
                Button {
                    zones.removeAll { $0.id == zone.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        Button("Add Zone") {
            let start = zones.last.map { $0.to ?? maximum } ?? maximum * 0.8
            zones.append(GaugeZone(from: start, to: nil, color: .red))
        }
    }
}
