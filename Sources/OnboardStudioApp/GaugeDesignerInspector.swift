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
            ChannelPicker(editor: editor, object: object, selection: field(\.channel, "Channel"))
            CommittingTextField("Title", text: field(\.title, "Title"))
            NumberField("Minimum", value: field(\.minValue, "Minimum"))
            NumberField("Maximum", value: field(\.maxValue, "Maximum"))
            NumberField("Major tick", value: field(\.majorTick, "Major Tick"))
            NumberField("Minor tick", value: field(\.minorTick, "Minor Tick"))
            if ChannelRole(identifier: params.channel) == .speed {
                if object.usesSpeedUnitPicker {
                    SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit, "Speed Unit"))
                } else {
                    DisplayUnitPicker(editor: editor, object: object)
                }
            } else {
                CommittingTextField("Unit label", text: field(\.unitLabel, "Unit Label"))
                NumberField("Divide value by", value: field(\.valueDivisor, "Divisor"))
            }
        }
        Section("Style") {
            Picker("Style", selection: field(\.style, "Gauge Style")) {
                Text("Needle").tag(GaugeStyle.needle)
                Text("Dual needle").tag(GaugeStyle.dualNeedle)
                Text("Filled arc").tag(GaugeStyle.arc)
            }
            NumberField("Sweep (°)", value: field(\.sweep, "Sweep"))
                .help("How far round the dial the scale runs, in degrees")
                .accessibilityIdentifier("gauge.sweep")
            NumberField("Rotation (°)", value: field(\.rotation, "Rotation"))
                .help("Turns the whole scale round the dial; 0 leaves the gap at the bottom")
            Toggle("Counter-clockwise", isOn: field(\.counterClockwise, "Direction"))
            if params.style == .dualNeedle {
                OptionalChannelPicker(
                    editor: editor, title: "Second needle",
                    selection: Binding(
                        get: { params.secondChannel.isEmpty ? nil : params.secondChannel },
                        set: { v in update("Second Needle Channel") { $0.secondChannel = v ?? "" } }))
                ColorPicker("Second needle colour", selection: color(\.secondNeedleColor, "Second Needle Colour"))
            }
            if params.style == .arc {
                PercentSlider("Arc width", value: field(\.arcWidth, "Arc Width"), range: 0.04...0.4)
                ColorPicker("Arc track", selection: color(\.arcTrackColor, "Arc Track Colour"))
            }
            ColorPicker(
                params.style == .arc ? "Arc colour" : "Needle colour",
                selection: color(\.needleColor, params.style == .arc ? "Arc Colour" : "Needle Colour"))
            ColorPicker("Text colour", selection: color(\.textColor, "Text Colour"))
        }
        if params.style != .arc {
            Section("Needle") {
                PercentSlider("Length", value: field(\.needle.length, "Needle Length"), range: 0.2...1)
                    .help("How far the needle reaches from the centre, as a share of the gauge's radius")
                PercentSlider("Tail", value: field(\.needle.tailLength, "Needle Tail"), range: 0...0.5)
                    .help("How far the needle continues back past the centre")
                PercentSlider("Width", value: field(\.needle.width, "Needle Width"), range: 0.01...0.2)
                    .help("How wide the needle is where it meets the hub")
                PercentSlider("Hub", value: field(\.needle.hubRadius, "Hub Size"), range: 0...0.3)
                    .help("The size of the disc the needle turns on; 0 hides it")
                Toggle("Tapered", isOn: field(\.needle.tapered, "Needle Taper"))
                    .help("Narrow the needle towards its tip")
                Slider(value: field(\.needle.smoothingSeconds, "Needle Smoothing"), in: 0...2) {
                    Text(
                        params.needle.smoothingSeconds == 0
                            ? "Smoothing off" : "Smoothing \(String(format: "%.1f", params.needle.smoothingSeconds)) s")
                }
            }
        }
        Section("Ticks & Labels") {
            Toggle("Major ticks", isOn: field(\.ticks.showMajor, "Major Ticks"))
            Toggle("Minor ticks", isOn: field(\.ticks.showMinor, "Minor Ticks"))
            Toggle("Labels", isOn: field(\.ticks.showLabels, "Tick Labels"))
            PercentSlider("Major length", value: field(\.ticks.majorLength, "Major Tick Length"), range: 0.02...0.4)
            PercentSlider("Minor length", value: field(\.ticks.minorLength, "Minor Tick Length"), range: 0.01...0.3)
            PercentSlider("Outer radius", value: field(\.ticks.outerRadius, "Tick Radius"), range: 0.5...1)
                .help("How far out the ticks reach, as a share of the gauge's radius")
            PercentSlider("Label radius", value: field(\.ticks.labelRadius, "Label Radius"), range: 0.3...1)
                .help("How far from the centre the numbers sit")
            PercentSlider("Label size", value: field(\.ticks.labelScale, "Label Size"), range: 0.05...0.3)
            Stepper(
                "Label decimals: \(params.ticks.labelDecimals)", value: field(\.ticks.labelDecimals, "Label Decimals"),
                in: 0...3)
            Toggle("Declutter crowded labels", isOn: field(\.ticks.declutter, "Label Decluttering"))
                .help("Leave out numbers that would overlap their neighbours")
        }
        Section("Zones") {
            ZoneListEditor(zones: field(\.zones, "Zones"), maximum: params.maxValue)
            Toggle("Paint band on face", isOn: field(\.zoneTargets.face, "Zone Band"))
            Toggle("Colour ticks and labels", isOn: field(\.zoneTargets.marks, "Zone Tick Colours"))
            Toggle(
                params.style == .arc ? "Colour arc" : "Colour needle",
                isOn: field(\.zoneTargets.needle, params.style == .arc ? "Zone Arc Colour" : "Zone Needle Colour"))
            Toggle("Blend colours (gradient)", isOn: field(\.zoneTargets.gradient, "Zone Blending"))
            Text("Colour part of the scale — amber from 6,500 rpm, red from 7,200 — and choose what the colour paints.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Face") {
            Toggle("Show face", isOn: field(\.showFace, "Face"))
            ColorPicker("Face colour", selection: color(\.faceColor, "Face Colour"))
            Picker("Face image", selection: field(\.faceImageInputID, "Face Image")) {
                Text("None").tag(InputID?.none)
                ForEach(editor.project.inputs.filter(\.kind.isImage)) { Text($0.label).tag(InputID?.some($0.id)) }
            }
            Button("Add Face Image…") { editor.addImageInput() }
        }
        Section("Readout") {
            Toggle("Show digital value", isOn: field(\.showValue, "Digital Value"))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals, "Decimals"), in: 0...3)
        }
    }

    /// A binding to one parameter. `name` is what changed, in title case, so Edit ▸ Undo reads
    /// *Undo Change Sweep* rather than one name for every control of the gauge (#208).
    func field<T>(_ keyPath: WritableKeyPath<GaugeParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { value in update(name) { $0[keyPath: keyPath] = value } })
    }

    func color(_ keyPath: WritableKeyPath<GaugeParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) },
            set: { value in update(name) { $0[keyPath: keyPath] = RGBAColor(value) } })
    }

    func update(_ name: String, _ change: (inout GaugeParams) -> Void) {
        var new = params
        change(&new)
        let kind: DisplayObjectKind =
            switch object.kind {
            case .speedometer: .speedometer(new)
            case .tachometer: .tachometer(new)
            default: .gauge(new)
            }
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = kind }
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
                    "Zone \(index + 1) colour",
                    selection: Binding(
                        get: { Color(zone.color) },
                        set: { c in if zones.indices.contains(index) { zones[index].color = RGBAColor(c) } })
                )
                .labelsHidden()
                NumberField(
                    "From",
                    value: Binding(
                        get: { zone.from }, set: { v in if zones.indices.contains(index) { zones[index].from = v } })
                )
                .accessibilityLabel("Zone \(index + 1) from")
                Text("to").accessibilityHidden(true)
                OptionalNumberField(
                    "Max",
                    value: Binding(
                        get: { zone.to }, set: { v in if zones.indices.contains(index) { zones[index].to = v } }),
                    placeholder: "max"
                )
                .accessibilityLabel("Zone \(index + 1) to")
                Button {
                    zones.removeAll { $0.id == zone.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this zone")
                .accessibilityLabel("Remove zone \(index + 1)")
            }
        }
        Button("Add Zone") {
            let start = zones.last.map { $0.to ?? maximum } ?? maximum * 0.8
            zones.append(GaugeZone(from: start, to: nil, color: .red))
        }
    }
}
