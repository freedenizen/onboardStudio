import ProjectModel
import SwiftUI
import TelemetryKit

struct BarInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: BarParams

    var body: some View {
        Section("Bar") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel, "Channel"))
            CommittingTextField("Caption", text: field(\.label, "Caption"))
            NumberField("Minimum", value: field(\.minValue, "Minimum"))
            NumberField("Maximum", value: field(\.maxValue, "Maximum"))
            Picker("Orientation", selection: orientation) {
                Text("Horizontal").tag(BarOrientation.horizontal)
                Text("Vertical").tag(BarOrientation.vertical)
            }
            Stepper(
                "Segments: \(params.segments == 0 ? "continuous" : String(params.segments))",
                value: field(\.segments, "Segments"),
                in: 0...40)
            PercentSlider("Corner radius", value: field(\.cornerRadius, "Corner Radius"), range: 0...0.5)
            ColorPicker("Fill", selection: color(\.fillColor, "Fill Colour"))
            ColorPicker("Track", selection: color(\.trackColor, "Track Colour"))
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
        }
        Section("Zones") {
            ZoneListEditor(zones: field(\.zones, "Zones"), maximum: params.maxValue)
            Toggle("Zone colours the fill (else the track)", isOn: field(\.zoneColorsFill, "Zone Fill Colouring"))
            Toggle("Fill from zero (± bar)", isOn: field(\.fillFromZero, "Fill From Zero"))
                .help(
                    "For deltas, steering or lateral g: the bar grows left or right of zero. Needs a range across zero."
                )
        }
        Section("Readout") {
            Toggle("Show value", isOn: field(\.showValue, "Value"))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals, "Decimals"), in: 0...3)
            if ChannelRole(identifier: params.channel) == .speed {
                if object.usesSpeedUnitPicker {
                    SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit, "Speed Unit"))
                } else {
                    DisplayUnitPicker(editor: editor, object: object)
                }
            } else {
                CommittingTextField("Unit label", text: field(\.unitLabel, "Unit Label"))
            }
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<BarParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<BarParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout BarParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .bar(new) }
    }

    /// Turning the bar turns its frame too, in the same undo step (#113).
    var orientation: Binding<BarOrientation> {
        Binding(
            get: { params.orientation },
            set: { value in
                let settings = editor.project.settings
                editor.updateObject(object.id, name: "Change Orientation") { $0.setBarOrientation(value, in: settings) }
            })
    }
}

struct GraphInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GraphParams

    var body: some View {
        Section("Graph") {
            CommittingTextField("Caption", text: field(\.label, "Caption"))
            Picker("Horizontal axis", selection: field(\.axis, "Horizontal Axis")) {
                Text("Time").tag(GraphAxis.time)
                Text("Distance").tag(GraphAxis.distance)
                Text("Current lap (distance)").tag(GraphAxis.lap)
            }
            if params.axis == .time {
                NumberField("Window (s)", value: field(\.window, "Window"))
            } else if params.axis == .distance {
                NumberField("Window (m)", value: field(\.window, "Window"))
            } else {
                Toggle("Show best lap as ghost", isOn: field(\.compareBestLap, "Ghost Lap"))
                ColorPicker("Ghost colour", selection: color(\.ghostColor, "Ghost Colour"))
            }
            NumberField(
                "Minimum (blank = auto)",
                value: Binding(
                    get: { params.minValue ?? .nan },
                    set: { v in update("Minimum") { $0.minValue = v.isNaN ? nil : v } }))
            NumberField(
                "Maximum (blank = auto)",
                value: Binding(
                    get: { params.maxValue ?? .nan },
                    set: { v in update("Maximum") { $0.maxValue = v.isNaN ? nil : v } }))
            Toggle(
                "Auto range",
                isOn: Binding(
                    get: { params.minValue == nil && params.maxValue == nil },
                    set: { auto in
                        update("Auto Range") {
                            $0.minValue = auto ? nil : 0
                            $0.maxValue = auto ? nil : 100
                        }
                    }))
            if object.usesSpeedUnitPicker {
                SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit, "Speed Unit"))
            } else {
                DisplayUnitPicker(editor: editor, object: object)
            }
        }
        Section("Series") {
            ForEach(params.series) { series in
                let index = params.series.firstIndex { $0.id == series.id } ?? 0
                HStack {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(series.color) },
                            set: { c in update("Series \(index + 1) Colour") { $0.series[index].color = RGBAColor(c) } }
                        )
                    )
                    .labelsHidden()
                    .accessibilityLabel("Series \(index + 1) colour")
                    ChannelPicker(
                        editor: editor, object: object,
                        selection: Binding(
                            get: { series.channel },
                            set: { v in update("Series \(index + 1) Channel") { $0.series[index].channel = v } })
                    )
                    .labelsHidden()
                    .accessibilityLabel("Series \(index + 1) channel")
                    Button {
                        update("Remove Series") { $0.series.removeAll { $0.id == series.id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(params.series.count <= 1)
                    .help("Remove this series")
                    .accessibilityLabel("Remove series \(index + 1)")
                }
                Toggle(
                    "Scale on its own",
                    isOn: Binding(
                        get: { series.usesOwnScale },
                        set: { v in update("Series \(index + 1) Own Scale") { $0.series[index].usesOwnScale = v } })
                )
                .accessibilityIdentifier("graph.ownScale")
                if series.usesOwnScale {
                    OptionalNumberField(
                        "Min",
                        value: Binding(
                            get: { series.minValue },
                            set: { v in update("Series \(index + 1) Minimum") { $0.series[index].minValue = v } }),
                        placeholder: "fit")
                    OptionalNumberField(
                        "Max",
                        value: Binding(
                            get: { series.maxValue },
                            set: { v in update("Series \(index + 1) Maximum") { $0.series[index].maxValue = v } }),
                        placeholder: "fit")
                }
            }
            Text(
                "A series on its own scale fills the plot whatever its numbers are, and is left out "
                    + "of the shared fit — which is how throttle in % and brake pressure in kPa can be "
                    + "read against each other."
            )
            .font(.caption).foregroundStyle(.secondary)
            Button("Add Series") {
                update("Add Series") { $0.series.append(GraphSeries(channel: "rpm", color: .white)) }
            }
            .disabled(params.series.count >= 4)
        }
        Section("Look") {
            Stepper("Grid lines: \(params.gridLines)", value: field(\.gridLines, "Grid Lines"), in: 0...8)
            Toggle("Fill under line", isOn: field(\.fillUnderLine, "Fill Under Line"))
            Toggle("Show cursor", isOn: field(\.showCursor, "Cursor"))
            Toggle("Show labels", isOn: field(\.showLabels, "Labels"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
            ColorPicker("Grid", selection: color(\.gridColor, "Grid Colour"))
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GraphParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<GraphParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout GraphParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .graph(new) }
    }
}

struct GearInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GearParams

    var body: some View {
        Section("Gear") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel, "Channel"))
            Toggle("Show caption", isOn: field(\.showLabel, "Caption Visibility"))
            CommittingTextField("Caption", text: field(\.label, "Caption"))
            CommittingTextField("Neutral", text: field(\.neutralText, "Neutral Text"))
            CommittingTextField("Reverse", text: field(\.reverseText, "Reverse Text"))
            CommittingTextField("Park", text: field(\.parkText, "Park Text"))
            PercentSlider("Glyph size", value: field(\.fontScale, "Glyph Size"), range: 0.3...1)
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GearParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<GearParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout GearParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .gear(new) }
    }
}

struct LapCounterInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: LapCounterParams

    var body: some View {
        Section("Lap Counter") {
            CommittingTextField("Caption", text: field(\.label, "Caption"))
            Toggle("Show total laps", isOn: field(\.showTotal, "Total Laps"))
            Stepper("Number offset: \(params.numberOffset)", value: field(\.numberOffset, "Number Offset"), in: -5...5)
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<LapCounterParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<LapCounterParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout LapCounterParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .lapCounter(new) }
    }
}

struct TimerInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TimerParams

    var body: some View {
        Section("Timer") {
            Picker("Shows", selection: field(\.mode, "Mode")) {
                ForEach(TimerMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            CommittingTextField(
                "Caption",
                text: Binding(
                    get: { params.label ?? "" }, set: { v in update("Caption") { $0.label = v.isEmpty ? nil : v } }),
                prompt: Text("default"))
            Toggle("Show lap number", isOn: field(\.showLapNumber, "Lap Number"))
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals, "Decimals"), in: 1...3)
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
            if params.mode == .deltaToBest || params.mode == .projectedLap {
                Picker("Compare with", selection: field(\.deltaReference, "Compare With")) {
                    ForEach(LapReference.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ColorPicker("Ahead colour", selection: color(\.aheadColor, "Ahead Colour"))
                ColorPicker("Behind colour", selection: color(\.behindColor, "Behind Colour"))
                Text("Needs a distance channel and a completed best lap.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<TimerParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<TimerParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout TimerParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .timer(new) }
    }
}

struct TextDataInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TextDataParams

    var body: some View {
        Section("Text Data") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel, "Channel"))
            CommittingTextField("Caption", text: field(\.label, "Caption"))
            Picker("Alignment", selection: field(\.alignment, "Alignment")) {
                Text("Leading").tag(ProjectModel.TextAlignment.leading)
                Text("Center").tag(ProjectModel.TextAlignment.center)
                Text("Trailing").tag(ProjectModel.TextAlignment.trailing)
            }
            if ChannelRole(identifier: params.channel) == .speed {
                if object.usesSpeedUnitPicker {
                    SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit, "Speed Unit"))
                } else {
                    DisplayUnitPicker(editor: editor, object: object)
                }
            } else {
                CommittingTextField("Unit label", text: field(\.unitLabel, "Unit Label"))
            }
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
        }
        Section("Warning Zones") {
            ZoneListEditor(zones: field(\.zones, "Zones"), maximum: 1000)
            Text("Recolour the number when the shown value falls in a zone (e.g. amber above 220, red above 235).")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Number Format") {
            Stepper("Decimals: \(params.decimals)", value: field(\.decimals, "Decimals"), in: 0...3)
            NumberField("Multiply by", value: field(\.multiplier, "Multiplier"))
            NumberField("Then add", value: field(\.offset, "Offset"))
            CommittingTextField("Prefix", text: field(\.prefix, "Prefix"))
            Toggle("Thousands separator", isOn: field(\.thousandsSeparator, "Thousands Separator"))
            Toggle("Show + sign", isOn: field(\.showPlusSign, "Plus Sign"))
            Toggle("Absolute value", isOn: field(\.absoluteValue, "Absolute Value"))
            Stepper(
                "Minimum digits: \(params.minimumIntegerDigits)",
                value: field(\.minimumIntegerDigits, "Minimum Digits"),
                in: 1...6)
        }
        Section("Text Size") {
            PercentSlider("Value size", value: field(\.fontScale, "Value Size"), range: 0.2...0.9)
            PercentSlider("Caption size", value: field(\.labelScale, "Caption Size"), range: 0.1...0.6)
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<TextDataParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<TextDataParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout TextDataParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .textData(new) }
    }
}

struct TrackMapInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TrackMapParams

    var body: some View {
        Section("Track Map") {
            NumberField("Rotation (°)", value: field(\.rotation, "Rotation"))
            NumberField("Line width", value: field(\.lineWidth, "Line Width"))
            NumberField("Dot radius", value: field(\.dotRadius, "Dot Radius"))
            ColorPicker("Line", selection: color(\.lineColor, "Line Colour"))
            ColorPicker("Dot", selection: color(\.dotColor, "Dot Colour"))
            ColorPicker("Panel", selection: color(\.backgroundColor, "Panel Colour"), supportsOpacity: true)
        }
        Section("Outline") {
            Picker("Draw from", selection: field(\.trace, "Draw From")) {
                ForEach(TrackMapTrace.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            switch params.trace {
            case .referenceLap:
                Text(
                    "The lap sectors and deltas are measured against — a crisper line, and one that "
                        + "leaves out the pit lane and the paddock."
                )
                .font(.caption).foregroundStyle(.secondary)
            case .trackOnly:
                Text(
                    "Every lap, but only where the car drove the circuit: the pit lane, the pit entry and "
                        + "exit and the paddock were driven once and the track was driven every lap. A session "
                        + "with too few laps to tell them apart is drawn whole."
                )
                .font(.caption).foregroundStyle(.secondary)
            case .wholeSession:
                Text("Every position in the file, including the pit lane and anywhere else the car was driven.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Colour by sector", isOn: field(\.colorBySector, "Sector Colouring"))
            Toggle("Sector boundary ticks", isOn: field(\.showSectorTicks, "Sector Ticks"))
            Toggle("Corner numbers", isOn: field(\.showCornerNumbers, "Corner Numbers"))
            if params.showSectorTicks || params.showCornerNumbers {
                ColorPicker("Labels", selection: color(\.labelColor, "Label Colour"))
                NumberField("Label size", value: field(\.labelScale, "Label Size"), fractionDigits: 0...2, step: 0.01)
            }
            if params.colorBySector || params.showSectorTicks {
                Text(sectorNote).font(.caption).foregroundStyle(.secondary)
            }
            if params.showCornerNumbers {
                Text("Corners are found from the reference lap's curvature, not from a published map.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Map Background") {
            Picker("Imagery", selection: field(\.background, "Map Background")) {
                ForEach(MapBackgroundStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if params.background != .none {
                Text("Fetched from Apple Maps for the session's area and cached; needs a network connection once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Second Vehicle") {
            Picker("Data input", selection: field(\.secondInputID, "Second Data Input")) {
                Text("None").tag(InputID?.none)
                ForEach(editor.project.dataInputs.filter { $0.id != object.inputID }) { input in
                    Text(input.label).tag(InputID?.some(input.id))
                }
            }
            if params.secondInputID != nil {
                ColorPicker("Second dot", selection: color(\.secondDotColor, "Second Dot Colour"))
                Text("Positions come from that input's own sync settings, so both cars share project time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// How many sectors this map's data input actually has, so the colouring says where it is
    /// set rather than leaving the driver hunting for it.
    var sectorNote: String {
        guard let session = object.inputID.flatMap({ editor.loaded?.sessions[$0] }), let analysis = session.sectors,
            analysis.count > 1
        else { return "This data file has no sectors yet — set them on the data input." }
        return "\(analysis.count) sectors, set on the data input."
    }

    func field<T>(_ keyPath: WritableKeyPath<TrackMapParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<TrackMapParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout TrackMapParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .trackMap(new) }
    }
}
