import ProjectModel
import SwiftUI
import TelemetryKit

struct InspectorView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Form {
            if let object = editor.selectedObject {
                ObjectInspector(editor: editor, object: object)
            } else if let input = editor.selectedInput {
                InputInspector(editor: editor, input: input)
            } else {
                ProjectInspector(editor: editor)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Project

struct ProjectInspector: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Section("Output") {
            Picker("Size", selection: sizeBinding) {
                ForEach(sizeOptions, id: \.self) { option in
                    Text(option.replacingOccurrences(of: "x", with: " × ")).tag(option)
                }
            }
            Picker("Frame rate", selection: frameRateBinding) {
                Text("24").tag(24.0)
                Text("25").tag(25.0)
                Text("30").tag(30.0)
                Text("50").tag(50.0)
                Text("60").tag(60.0)
            }
        }
        Section {
            Text(
                "Select an input or a display object to edit it. Drag objects on the preview to move them; "
                    + "drag their handles to resize (⇧ keeps the aspect ratio)."
            )
            .font(.callout).foregroundStyle(.secondary)
        }
    }

    var sizeOptions: [String] {
        let presets = ["1280x720", "1920x1080", "2560x1440", "3840x2160"]
        let current = "\(editor.project.settings.outputWidth)x\(editor.project.settings.outputHeight)"
        return presets.contains(current) ? presets : [current] + presets
    }

    var sizeBinding: Binding<String> {
        Binding(
            get: { "\(editor.project.settings.outputWidth)x\(editor.project.settings.outputHeight)" },
            set: { value in
                let parts = value.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                editor.edit("Change Output Size") {
                    $0.settings.outputWidth = parts[0]
                    $0.settings.outputHeight = parts[1]
                    $0.export.width = parts[0]
                    $0.export.height = parts[1]
                }
            })
    }

    var frameRateBinding: Binding<Double> {
        Binding(
            get: { editor.project.settings.frameRate },
            set: { value in
                editor.edit("Change Frame Rate") {
                    $0.settings.frameRate = value
                    $0.export.frameRate = value
                }
            })
    }
}

// MARK: - Input

struct InputInspector: View {
    @Bindable var editor: EditorModel
    let input: Input

    var body: some View {
        Section(input.kind.isVideo ? "Video" : "Data") {
            LabeledContent("File", value: input.source.path).font(.caption)
            TextField("Label", text: binding(\.label, name: "Rename Input"))
            if let session = editor.sessions[input.id] {
                LabeledContent("Format", value: session.info.sourceFormat)
                LabeledContent("Channels", value: "\(session.channels.count)")
                LabeledContent("Laps", value: "\(session.laps.count)")
                if let range = session.timeRange {
                    LabeledContent("Time range", value: "\(fmt(range.lowerBound)) – \(fmt(range.upperBound)) s")
                }
            }
            if let info = editor.loaded?.mediaInfo[input.id] {
                LabeledContent("Size", value: "\(info.width) × \(info.height)")
                LabeledContent("Duration", value: "\(fmt(info.duration)) s")
                LabeledContent("Frame rate", value: fmt(info.nominalFrameRate))
            }
        }
        Section("Synchronization") {
            NumberField(
                "Start position in file (s)", value: binding(\.sync.startPositionInInput, name: "Change Start Position")
            )
            NumberField("Offset in project (s)", value: binding(\.sync.offsetInProject, name: "Change Offset"))
            NumberField("Play speed", value: binding(\.sync.playSpeed, name: "Change Speed"))
            if !input.kind.isVideo {
                Button("Synchronize with Video…") { editor.showSyncWizard = true }
            }
        }
        if case .video(let settings) = input.kind {
            Section("Audio") {
                Toggle(
                    "Include audio",
                    isOn: Binding(
                        get: { settings.includeAudio },
                        set: { value in
                            editor.updateInput(input.id, name: "Toggle Audio") {
                                $0.kind = .video(VideoInputSettings(trim: settings.trim, includeAudio: value))
                            }
                        }))
            }
        }
        Section {
            Button("Remove Input", role: .destructive) { editor.removeInput(input.id) }
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<Input, T>, name: String) -> Binding<T> {
        Binding(
            get: { editor.project.input(input.id)?[keyPath: keyPath] ?? input[keyPath: keyPath] },
            set: { value in editor.updateInput(input.id, name: name) { $0[keyPath: keyPath] = value } })
    }
}

// MARK: - Display object

struct ObjectInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject

    var body: some View {
        Section(object.kind.typeName) {
            TextField("Label", text: binding(\.label, name: "Rename Object"))
            if object.kind.needsData {
                Picker("Data", selection: inputBinding) {
                    Text("None").tag(InputID?.none)
                    ForEach(editor.project.dataInputs) { Text($0.label).tag(InputID?.some($0.id)) }
                }
            }
            Toggle("Visible", isOn: binding(\.isVisible, name: "Toggle Visibility"))
            Slider(value: binding(\.opacity, name: "Change Opacity"), in: 0...1) { Text("Opacity") }
        }
        Section("Position & Size (% of frame)") {
            NumberField("X", value: percent(\.frame.x))
            NumberField("Y", value: percent(\.frame.y))
            NumberField("Width", value: percent(\.frame.width))
            NumberField("Height", value: percent(\.frame.height))
        }
        kindSection
        Section {
            Button("Delete Object", role: .destructive) {
                editor.selectedObjectID = object.id
                editor.deleteSelectedObject()
            }
        }
    }

    @ViewBuilder var kindSection: some View {
        switch object.kind {
        case .video:
            EmptyView()
        case .speedometer(let params), .tachometer(let params), .gauge(let params):
            GaugeInspector(editor: editor, object: object, params: params)
        case .trackMap(let params):
            Section("Track Map") {
                NumberField(
                    "Rotation (°)",
                    value: Binding(
                        get: { params.rotation },
                        set: { v in
                            set(
                                .trackMap(
                                    {
                                        var p = params
                                        p.rotation = v
                                        return p
                                    }()))
                        }))
                NumberField(
                    "Line width",
                    value: Binding(
                        get: { params.lineWidth },
                        set: { v in
                            set(
                                .trackMap(
                                    {
                                        var p = params
                                        p.lineWidth = v
                                        return p
                                    }()))
                        }))
            }
        case .gForce(let params):
            Section("G-Force") {
                NumberField(
                    "Max G",
                    value: Binding(
                        get: { params.maxG },
                        set: { v in
                            set(
                                .gForce(
                                    {
                                        var p = params
                                        p.maxG = max(0.5, v)
                                        return p
                                    }()))
                        }))
                NumberField(
                    "Trail (s)",
                    value: Binding(
                        get: { params.trailSeconds },
                        set: { v in
                            set(
                                .gForce(
                                    {
                                        var p = params
                                        p.trailSeconds = max(0, v)
                                        return p
                                    }()))
                        }))
                Toggle(
                    "Show values",
                    isOn: Binding(
                        get: { params.showValues },
                        set: { v in
                            set(
                                .gForce(
                                    {
                                        var p = params
                                        p.showValues = v
                                        return p
                                    }()))
                        }))
            }
        case .timer(let params):
            Section("Timer") {
                Picker(
                    "Shows",
                    selection: Binding(
                        get: { params.mode },
                        set: { v in
                            set(
                                .timer(
                                    {
                                        var p = params
                                        p.mode = v
                                        return p
                                    }()))
                        })
                ) {
                    Text("Current lap").tag(TimerMode.currentLap)
                    Text("Last lap").tag(TimerMode.lastLap)
                    Text("Best lap").tag(TimerMode.bestLap)
                    Text("Session time").tag(TimerMode.session)
                }
                Toggle(
                    "Show lap number",
                    isOn: Binding(
                        get: { params.showLapNumber },
                        set: { v in
                            set(
                                .timer(
                                    {
                                        var p = params
                                        p.showLapNumber = v
                                        return p
                                    }()))
                        }))
            }
        case .textData(let params):
            Section("Text Data") {
                ChannelPicker(
                    editor: editor, object: object,
                    selection: Binding(
                        get: { params.channel },
                        set: { v in
                            set(
                                .textData(
                                    {
                                        var p = params
                                        p.channel = v
                                        return p
                                    }()))
                        }))
                TextField(
                    "Caption",
                    text: Binding(
                        get: { params.label },
                        set: { v in
                            set(
                                .textData(
                                    {
                                        var p = params
                                        p.label = v
                                        return p
                                    }()))
                        }))
                Stepper(
                    "Decimals: \(params.decimals)",
                    value: Binding(
                        get: { params.decimals },
                        set: { v in
                            set(
                                .textData(
                                    {
                                        var p = params
                                        p.decimals = max(0, min(3, v))
                                        return p
                                    }()))
                        }))
                SpeedUnitPicker(
                    selection: Binding(
                        get: { params.speedUnit },
                        set: { v in
                            set(
                                .textData(
                                    {
                                        var p = params
                                        p.speedUnit = v
                                        return p
                                    }()))
                        }))
                Picker(
                    "Alignment",
                    selection: Binding(
                        get: { params.alignment },
                        set: { v in
                            set(
                                .textData(
                                    {
                                        var p = params
                                        p.alignment = v
                                        return p
                                    }()))
                        })
                ) {
                    Text("Leading").tag(ProjectModel.TextAlignment.leading)
                    Text("Center").tag(ProjectModel.TextAlignment.center)
                    Text("Trailing").tag(ProjectModel.TextAlignment.trailing)
                }
            }
        }
    }

    func set(_ kind: DisplayObjectKind) {
        editor.updateObject(object.id, name: "Edit \(object.kind.typeName)") { $0.kind = kind }
    }

    func binding<T>(_ keyPath: WritableKeyPath<DisplayObject, T>, name: String) -> Binding<T> {
        Binding(
            get: { editor.project.displayObject(object.id)?[keyPath: keyPath] ?? object[keyPath: keyPath] },
            set: { value in editor.updateObject(object.id, name: name) { $0[keyPath: keyPath] = value } })
    }

    func percent(_ keyPath: WritableKeyPath<DisplayObject, Double>) -> Binding<Double> {
        Binding(
            get: { ((editor.project.displayObject(object.id)?[keyPath: keyPath] ?? 0) * 100).rounded() },
            set: { value in
                editor.updateObject(object.id, name: "Move Object") {
                    $0[keyPath: keyPath] = min(max(value / 100, 0), 1)
                }
            })
    }

    var inputBinding: Binding<InputID?> {
        Binding(
            get: { object.inputID },
            set: { value in editor.updateObject(object.id, name: "Change Data Source") { $0.inputID = value } })
    }
}

struct GaugeInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GaugeParams

    var body: some View {
        Section("Gauge") {
            ChannelPicker(editor: editor, object: object, selection: field(\.channel))
            TextField("Title", text: field(\.title))
            NumberField("Minimum", value: field(\.minValue))
            NumberField("Maximum", value: field(\.maxValue))
            NumberField("Major tick", value: field(\.majorTick))
            NumberField("Minor tick", value: field(\.minorTick))
            NumberField("Sweep (°)", value: field(\.sweep))
            NumberField("Rotation (°)", value: field(\.rotation))
            NumberField(
                "Red zone from",
                value: Binding(
                    get: { params.redlineFrom ?? 0 }, set: { v in update { $0.redlineFrom = v > 0 ? v : nil } }))
            if ChannelRole(identifier: params.channel) == .speed {
                SpeedUnitPicker(selection: field(\.speedUnit))
            } else {
                TextField("Unit label", text: field(\.unitLabel))
                NumberField("Divide value by", value: field(\.valueDivisor))
            }
            Toggle("Show digital value", isOn: field(\.showValue))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GaugeParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
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

// MARK: - Controls

struct ChannelPicker: View {
    let editor: EditorModel
    let object: DisplayObject
    @Binding var selection: String

    var body: some View {
        let session = object.inputID.flatMap { editor.sessions[$0] }
        let available = session?.orderedChannels.map(\.role.identifier) ?? []
        let options = available.contains(selection) || selection.isEmpty ? available : [selection] + available
        Picker("Channel", selection: $selection) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }
}

struct SpeedUnitPicker: View {
    @Binding var selection: SpeedDisplayUnit

    var body: some View {
        Picker("Speed unit", selection: $selection) {
            ForEach(SpeedDisplayUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double

    init(_ title: String, value: Binding<Double>) {
        self.title = title
        _value = value
    }

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(0...3)))
    }
}

private func fmt(_ value: Double) -> String {
    value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
}
