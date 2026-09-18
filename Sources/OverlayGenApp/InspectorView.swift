import ProjectModel
import SwiftUI
import TelemetryKit

struct InspectorView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Form {
            if let object = editor.selectedObject {
                ObjectInspector(editor: editor, object: object)
            } else if let segment = editor.selectedSegment {
                SegmentInspector(editor: editor, segment: segment)
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
            VideoInputInspector(editor: editor, input: input, settings: settings)
        }
        if case .data(let settings) = input.kind {
            DataInputInspector(editor: editor, input: input, settings: settings)
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
            OverrideRow(editor: editor, object: object, property: .isVisible) {
                Toggle("Visible", isOn: visibleBinding)
            }
            OverrideRow(editor: editor, object: object, property: .opacity) {
                Slider(value: opacityBinding, in: 0...1) { Text("Opacity") }
            }
        }
        Section {
            NumberField("X", value: percent(\.x))
            NumberField("Y", value: percent(\.y))
            NumberField("Width", value: percent(\.width))
            NumberField("Height", value: percent(\.height))
        } header: {
            OverrideRow(editor: editor, object: object, property: .frame) { Text("Position & Size (% of frame)") }
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
        case .video(let params):
            VideoObjectInspector(editor: editor, object: object, params: params)
        case .shape(let params):
            ShapeInspector(editor: editor, object: object, params: params)
        case .text(let params):
            TextInspector(editor: editor, object: object, params: params)
        case .image(let params):
            ImageObjectInspector(editor: editor, object: object, params: params)
        case .speedometer(let params), .tachometer(let params), .gauge(let params):
            GaugeDesignerInspector(editor: editor, object: object, params: params)
        case .bar(let params):
            BarInspector(editor: editor, object: object, params: params)
        case .graph(let params):
            GraphInspector(editor: editor, object: object, params: params)
        case .gear(let params):
            GearInspector(editor: editor, object: object, params: params)
        case .lapCounter(let params):
            LapCounterInspector(editor: editor, object: object, params: params)
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
            TimerInspector(editor: editor, object: object, params: params)
        case .textData(let params):
            TextDataInspector(editor: editor, object: object, params: params)
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

    /// The object as it appears at the playhead (segment overrides applied).
    var resolved: DisplayObject { editor.resolvedObject(object.id) ?? object }

    var visibleBinding: Binding<Bool> {
        Binding(
            get: { resolved.isVisible },
            set: { value in editor.setOverridable(object.id, name: "Toggle Visibility") { $0.isVisible = value } })
    }

    var opacityBinding: Binding<Double> {
        Binding(
            get: { resolved.opacity },
            set: { value in editor.setOverridable(object.id, name: "Change Opacity") { $0.opacity = value } })
    }

    func percent(_ keyPath: WritableKeyPath<UnitRect, Double>) -> Binding<Double> {
        Binding(
            get: { (resolved.frame[keyPath: keyPath] * 100).rounded() },
            set: { value in
                var frame = resolved.frame
                frame[keyPath: keyPath] = min(max(value / 100, 0), 1)
                editor.setOverridable(object.id, name: "Move Object") { $0.frame = frame }
            })
    }

    var inputBinding: Binding<InputID?> {
        Binding(
            get: { object.inputID },
            set: { value in editor.updateObject(object.id, name: "Change Data Source") { $0.inputID = value } })
    }
}

/// Wraps a control for an overridable property with a badge showing whether the segment at the
/// playhead sets it, and a button to inherit it again.
struct OverrideRow<Content: View>: View {
    let editor: EditorModel
    let object: DisplayObject
    let property: OverridableProperty
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            content()
            if let segment = editor.editingSegment {
                if editor.isOverriddenHere(property, object.id) {
                    Button {
                        editor.resetOverride(property, object.id)
                    } label: {
                        Label(
                            "Set in \(segment.label.isEmpty ? "this segment" : segment.label)", systemImage: "pin.fill"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .help("Set in \(segment.label.isEmpty ? "this segment" : segment.label). Click to inherit instead.")
                } else {
                    Image(systemName: "pin.slash").foregroundStyle(.secondary)
                        .help("Inherited from earlier segments; editing sets it for this segment.")
                }
            }
        }
    }
}

struct SegmentInspector: View {
    @Bindable var editor: EditorModel
    let segment: Segment

    var body: some View {
        Section("Segment") {
            TextField(
                "Label", text: Binding(get: { segment.label }, set: { editor.renameSegment(segment.id, to: $0) }))
            NumberField(
                "Start (s)", value: Binding(get: { segment.start }, set: { editor.shiftSegment(segment.id, to: $0) }),
                fractionDigits: 0...3)
            Text("Moving a segment shifts every later segment by the same amount.").font(.caption)
                .foregroundStyle(.secondary)
            Button("Go to Segment") { editor.seek(to: segment.start) }
        }
        Section("Overrides") {
            let names = segment.overrides.keys.compactMap { editor.project.displayObject($0)?.label }.sorted()
            if names.isEmpty {
                Text("No object changes yet. Seek into this segment and edit visibility, position or opacity.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(names, id: \.self) { Text($0) }
            }
        }
        Section("Camera Layout") {
            ForEach(LayoutPreset.allCases, id: \.self) { preset in
                Button(preset.displayName) {
                    editor.seek(to: segment.start)
                    editor.applyLayout(preset)
                }
            }
            .disabled(editor.project.videoObjects.isEmpty)
        }
        Section {
            Button("Delete Segment", role: .destructive) { editor.deleteSegment(segment.id) }
        }
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
    let fractionDigits: ClosedRange<Int>

    init(_ title: String, value: Binding<Double>, fractionDigits: ClosedRange<Int> = 0...3) {
        self.title = title
        _value = value
        self.fractionDigits = fractionDigits
    }

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(fractionDigits)))
    }
}

private func fmt(_ value: Double) -> String {
    value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
}
