import ProjectModel
import SwiftUI
import TelemetryKit

struct BarInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: BarParams

    var body: some View {
        Section("Bar") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            TextField("Caption", text: field(\.label))
            NumberField("Minimum", value: field(\.minValue))
            NumberField("Maximum", value: field(\.maxValue))
            Picker("Orientation", selection: field(\.orientation)) {
                Text("Horizontal").tag(BarOrientation.horizontal)
                Text("Vertical").tag(BarOrientation.vertical)
            }
            Stepper(
                "Segments: \(params.segments == 0 ? "continuous" : String(params.segments))", value: field(\.segments),
                in: 0...40)
            PercentSlider("Corner radius", value: field(\.cornerRadius), range: 0...0.5)
            ColorPicker("Fill", selection: color(\.fillColor))
            ColorPicker("Track", selection: color(\.trackColor))
            ColorPicker("Text", selection: color(\.textColor))
        }
        Section("Zones") {
            ZoneListEditor(zones: field(\.zones), maximum: params.maxValue)
            Toggle("Zone colours the fill (else the track)", isOn: field(\.zoneColorsFill))
            Toggle("Fill from zero (± bar)", isOn: field(\.fillFromZero))
                .help(
                    "For deltas, steering or lateral g: the bar grows left or right of zero. Needs a range across zero."
                )
        }
        Section("Readout") {
            Toggle("Show value", isOn: field(\.showValue))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals), in: 0...3)
            if ChannelRole(identifier: params.channel) == .speed {
                SpeedUnitPicker(selection: field(\.speedUnit))
            } else {
                TextField("Unit label", text: field(\.unitLabel))
            }
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<BarParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<BarParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout BarParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Bar") { $0.kind = .bar(new) }
    }
}

struct GraphInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GraphParams

    var body: some View {
        Section("Graph") {
            TextField("Caption", text: field(\.label))
            Picker("Horizontal axis", selection: field(\.axis)) {
                Text("Time").tag(GraphAxis.time)
                Text("Distance").tag(GraphAxis.distance)
                Text("Current lap (distance)").tag(GraphAxis.lap)
            }
            if params.axis == .time {
                NumberField("Window (s)", value: field(\.window))
            } else if params.axis == .distance {
                NumberField("Window (m)", value: field(\.window))
            } else {
                Toggle("Show best lap as ghost", isOn: field(\.compareBestLap))
                ColorPicker("Ghost colour", selection: color(\.ghostColor))
            }
            NumberField(
                "Minimum (blank = auto)",
                value: Binding(
                    get: { params.minValue ?? .nan }, set: { v in update { $0.minValue = v.isNaN ? nil : v } }))
            NumberField(
                "Maximum (blank = auto)",
                value: Binding(
                    get: { params.maxValue ?? .nan }, set: { v in update { $0.maxValue = v.isNaN ? nil : v } }))
            Toggle(
                "Auto range",
                isOn: Binding(
                    get: { params.minValue == nil && params.maxValue == nil },
                    set: { auto in
                        update {
                            $0.minValue = auto ? nil : 0
                            $0.maxValue = auto ? nil : 100
                        }
                    }))
            SpeedUnitPicker(selection: field(\.speedUnit))
        }
        Section("Series") {
            ForEach(params.series) { series in
                let index = params.series.firstIndex { $0.id == series.id } ?? 0
                HStack {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(series.color) }, set: { c in update { $0.series[index].color = RGBAColor(c) } }
                        )
                    )
                    .labelsHidden()
                    ChannelPicker(
                        editor: editor, object: object,
                        selection: Binding(
                            get: { series.channel }, set: { v in update { $0.series[index].channel = v } })
                    )
                    .labelsHidden()
                    Button {
                        update { $0.series.removeAll { $0.id == series.id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(params.series.count <= 1)
                }
            }
            Button("Add Series") {
                update { $0.series.append(GraphSeries(channel: "rpm", color: .white)) }
            }
            .disabled(params.series.count >= 4)
        }
        Section("Look") {
            Stepper("Grid lines: \(params.gridLines)", value: field(\.gridLines), in: 0...8)
            Toggle("Fill under line", isOn: field(\.fillUnderLine))
            Toggle("Show cursor", isOn: field(\.showCursor))
            Toggle("Show labels", isOn: field(\.showLabels))
            ColorPicker("Background", selection: color(\.backgroundColor))
            ColorPicker("Grid", selection: color(\.gridColor))
            ColorPicker("Text", selection: color(\.textColor))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GraphParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<GraphParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout GraphParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Graph") { $0.kind = .graph(new) }
    }
}

struct GearInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GearParams

    var body: some View {
        Section("Gear") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            Toggle("Show caption", isOn: field(\.showLabel))
            TextField("Caption", text: field(\.label))
            TextField("Neutral", text: field(\.neutralText))
            TextField("Reverse", text: field(\.reverseText))
            TextField("Park", text: field(\.parkText))
            PercentSlider("Glyph size", value: field(\.fontScale), range: 0.3...1)
            ColorPicker("Text", selection: color(\.textColor))
            ColorPicker("Background", selection: color(\.backgroundColor))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GearParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<GearParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout GearParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Gear") { $0.kind = .gear(new) }
    }
}

struct LapCounterInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: LapCounterParams

    var body: some View {
        Section("Lap Counter") {
            TextField("Caption", text: field(\.label))
            Toggle("Show total laps", isOn: field(\.showTotal))
            Stepper("Number offset: \(params.numberOffset)", value: field(\.numberOffset), in: -5...5)
            ColorPicker("Text", selection: color(\.textColor))
            ColorPicker("Background", selection: color(\.backgroundColor))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<LapCounterParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<LapCounterParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout LapCounterParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Lap Counter") { $0.kind = .lapCounter(new) }
    }
}

struct TimerInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TimerParams

    var body: some View {
        Section("Timer") {
            Picker("Shows", selection: field(\.mode)) {
                ForEach(TimerMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            TextField(
                "Caption",
                text: Binding(get: { params.label ?? "" }, set: { v in update { $0.label = v.isEmpty ? nil : v } }),
                prompt: Text("default"))
            Toggle("Show lap number", isOn: field(\.showLapNumber))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals), in: 1...3)
            ColorPicker("Text", selection: color(\.textColor))
            ColorPicker("Background", selection: color(\.backgroundColor))
            if params.mode == .deltaToBest {
                Picker("Compare with", selection: field(\.deltaReference)) {
                    ForEach(LapReference.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ColorPicker("Ahead colour", selection: color(\.aheadColor))
                ColorPicker("Behind colour", selection: color(\.behindColor))
                Text("Needs a distance channel and a completed best lap.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<TimerParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<TimerParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout TimerParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Timer") { $0.kind = .timer(new) }
    }
}

struct TextDataInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TextDataParams

    var body: some View {
        Section("Text Data") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            TextField("Caption", text: field(\.label))
            Picker("Alignment", selection: field(\.alignment)) {
                Text("Leading").tag(ProjectModel.TextAlignment.leading)
                Text("Center").tag(ProjectModel.TextAlignment.center)
                Text("Trailing").tag(ProjectModel.TextAlignment.trailing)
            }
            if ChannelRole(identifier: params.channel) == .speed {
                SpeedUnitPicker(selection: field(\.speedUnit))
            } else {
                TextField("Unit label", text: field(\.unitLabel))
            }
            ColorPicker("Text", selection: color(\.textColor))
            ColorPicker("Background", selection: color(\.backgroundColor))
        }
        Section("Warning Zones") {
            ZoneListEditor(zones: field(\.zones), maximum: 1000)
            Text("Recolour the number when the shown value falls in a zone (e.g. amber above 220, red above 235).")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Number Format") {
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals), in: 0...3)
            NumberField("Multiply by", value: field(\.multiplier))
            NumberField("Then add", value: field(\.offset))
            TextField("Prefix", text: field(\.prefix))
            Toggle("Thousands separator", isOn: field(\.thousandsSeparator))
            Toggle("Show + sign", isOn: field(\.showPlusSign))
            Toggle("Absolute value", isOn: field(\.absoluteValue))
            Stepper("Minimum digits: \(params.minimumIntegerDigits)", value: field(\.minimumIntegerDigits), in: 1...6)
        }
        Section("Font") {
            PercentSlider("Value size", value: field(\.fontScale), range: 0.2...0.9)
            PercentSlider("Caption size", value: field(\.labelScale), range: 0.1...0.6)
            TextField("Font (blank = monospaced)", text: field(\.fontName))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<TextDataParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<TextDataParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout TextDataParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Text Data") { $0.kind = .textData(new) }
    }
}

struct TrackMapInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TrackMapParams

    var body: some View {
        Section("Track Map") {
            NumberField("Rotation (°)", value: field(\.rotation))
            NumberField("Line width", value: field(\.lineWidth))
            NumberField("Dot radius", value: field(\.dotRadius))
            ColorPicker("Line", selection: color(\.lineColor))
            ColorPicker("Dot", selection: color(\.dotColor))
            ColorPicker("Panel", selection: color(\.backgroundColor), supportsOpacity: true)
        }
        Section("Map Background") {
            Picker("Imagery", selection: field(\.background)) {
                ForEach(MapBackgroundStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if params.background != .none {
                Text("Fetched from Apple Maps for the session's area and cached; needs a network connection once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Second Vehicle") {
            Picker("Data input", selection: field(\.secondInputID)) {
                Text("None").tag(InputID?.none)
                ForEach(editor.project.dataInputs.filter { $0.id != object.inputID }) { input in
                    Text(input.label).tag(InputID?.some(input.id))
                }
            }
            if params.secondInputID != nil {
                ColorPicker("Second dot", selection: color(\.secondDotColor))
                Text("Positions come from that input's own sync settings, so both cars share project time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<TrackMapParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<TrackMapParams, RGBAColor>) -> Binding<Color> {
        Binding(get: { Color(params[keyPath: keyPath]) }, set: { v in update { $0[keyPath: keyPath] = RGBAColor(v) } })
    }

    func update(_ change: (inout TrackMapParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Track Map") { $0.kind = .trackMap(new) }
    }
}
