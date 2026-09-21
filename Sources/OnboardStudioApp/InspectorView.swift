import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

struct InspectorView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Form {
            if let object = editor.selectedObject {
                ObjectInspector(editor: editor, object: object)
            } else if let marker = editor.selectedMarker {
                MarkerInspector(editor: editor, marker: marker)
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
        OverlayOpacitySection(editor: editor)
        CameraFramingSection(editor: editor)
        GettingStartedSection(editor: editor)
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
            if let problem = editor.problems[input.id] {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.callout)
                Button("Relink…") { editor.relink(input.id) }
            }
            TextField("Label", text: binding(\.label, name: "Rename Input")).accessibilityIdentifier("input.label")
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
                if info.hasGPMF {
                    Button("Use Embedded GPS") { editor.useEmbeddedTelemetry(of: input.id) }
                    Text("This GoPro recording carries GPS, accelerometer and gyro data.").font(.caption)
                        .foregroundStyle(.secondary)
                } else if let companion = info.companion {
                    Button("Use Sidecar Data (\(companion.displayName))") { editor.useEmbeddedTelemetry(of: input.id) }
                    Text("\(companion.url.lastPathComponent) was recorded with this video.").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        Section("Synchronization") {
            NumberField(
                "Start position in file (s)", value: binding(\.sync.startPositionInInput, name: "Change Start Position")
            )
            .accessibilityIdentifier("sync.startPosition")
            NumberField("Offset in project (s)", value: binding(\.sync.offsetInProject, name: "Change Offset"))
                .accessibilityIdentifier("sync.offset")
            NumberField("Play speed", value: binding(\.sync.playSpeed, name: "Change Speed"))
                .accessibilityIdentifier("sync.speed")
            if input.kind.isVideo {
                HStack {
                    Button("Start After Previous Video") { editor.chainAfterPreviousVideo(input.id) }
                        .disabled(editor.previousVideo(before: input.id) == nil)
                    Button("Start at 0") { editor.setOffset(of: input.id, to: 0, name: "Move Video to Start") }
                        .disabled(input.sync.offsetInProject == 0)
                }
                if let end = editor.end(of: input) {
                    Text("Plays from \(fmt(input.sync.offsetInProject)) s to \(fmt(end)) s of the project.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Order").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editor.moveInput(input.id, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(editor.project.inputs.first?.id == input.id)
                    Button {
                        editor.moveInput(input.id, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(editor.project.inputs.last?.id == input.id)
                }
                Text("Drag the video bars in the timeline to move them; videos snap to each other's ends.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !input.kind.isVideo {
                Button("Synchronize with Video…") { editor.showSyncWizard = true }
                if let suggestion = editor.suggestedSync(for: input.id) {
                    Button("Auto-Sync from Timestamps") { editor.autoSync(input.id) }
                    Text("Aligns the data's clock with the video's \(suggestion.videoClock).").font(.caption)
                        .foregroundStyle(.secondary)
                }
                if input.kind.isData, !editor.project.videoInputs.isEmpty {
                    if let progress = editor.motionSyncProgress {
                        HStack {
                            if progress > 0 {
                                ProgressView(value: progress) { Text("Analysing picture motion…") }
                            } else {
                                ProgressView { Text("Listening to the audio…") }
                            }
                            Button("Cancel") { editor.cancelMotionSync() }
                        }
                    } else {
                        Button("Auto-Sync by Motion") { editor.motionSync(input.id) }
                            .disabled(editor.motionSyncTask != nil)
                        Text("Matches the video's sound and motion against the log's speed; needs no clocks.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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
            TextField("Label", text: binding(\.label, name: "Rename Object")).accessibilityIdentifier("object.label")
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
            NumberField("X", value: percent(\.x)).accessibilityIdentifier("object.x")
            NumberField("Y", value: percent(\.y)).accessibilityIdentifier("object.y")
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
        case .scripted(let params):
            ScriptInspector(editor: editor, object: object, params: params)
        case .indicator(let params):
            IndicatorInspector(editor: editor, object: object, params: params)
        case .steeringWheel(let params):
            SteeringWheelInspector(editor: editor, object: object, params: params)
        case .lapPanel(let params):
            LapPanelInspector(editor: editor, object: object, params: params)
        case .sectorPanel(let params):
            SectorPanelInspector(editor: editor, object: object, params: params)
        case .trackMap(let params):
            TrackMapInspector(editor: editor, object: object, params: params)
        case .gForce(let params):
            GForceInspector(editor: editor, object: object, params: params)
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
                frame[keyPath: keyPath] = value / 100
                // Negative positions and sizes past 100% are legitimate: objects may hang off
                // the frame, as the Glass Cockpit steering wheel does.
                frame = ObjectGeometry.clamped(frame)
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
        let missing = !selection.isEmpty && !available.isEmpty && !available.contains(selection)
        let options = (selection.isEmpty ? [""] : missing ? [selection] : []) + available
        Picker("Channel", selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(option.isEmpty ? "Choose a channel…" : option).tag(option)
            }
        }
        if missing {
            Label(
                "\"\(selection)\" is not in this data input; pick one of its channels.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.yellow).font(.caption)
        } else if selection.isEmpty, !available.isEmpty {
            Label("This object needs a channel.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow).font(.caption)
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

private func fmt(_ value: Double) -> String {
    value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
}

/// The selected marker: what it is called, what colour it is, and how long it runs.
struct MarkerInspector: View {
    @Bindable var editor: EditorModel
    let marker: Marker

    var body: some View {
        Section("Marker") {
            TextField(
                "Name",
                text: Binding(
                    get: { marker.name },
                    set: { editor.renameMarker(marker.id, to: $0) })
            )
            .accessibilityIdentifier("marker.name")
            ColorPicker(
                "Colour",
                selection: Binding(
                    get: { Color(marker.colour) },
                    set: { colour in
                        editor.updateMarker(marker.id, name: "Recolour Marker") { $0.colour = RGBAColor(colour) }
                    }
                ))
            // 0 keeps it a flag; anything more draws it as a bar, which is how a sector or an
            // incident that lasts is told apart from a moment.
            NumberField(
                "Length (s)",
                value: Binding(
                    get: { marker.duration },
                    set: { value in
                        editor.updateMarker(marker.id, name: "Resize Marker") { $0.duration = max(0, value) }
                    }), fractionDigits: 0...2)
            TextField(
                "Note",
                text: Binding(
                    get: { marker.note },
                    set: { note in editor.updateMarker(marker.id, name: "Annotate Marker") { $0.note = note } }),
                axis: .vertical)
            if let input = marker.inputID.flatMap(editor.project.input) {
                Text("Belongs to \(input.label), so it moves when that input is re-synced.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Belongs to the timeline, so it stays at this time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Delete Marker", role: .destructive) { editor.deleteMarker(marker.id) }
        }
    }
}
