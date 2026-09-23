import ProjectModel
import SwiftUI

struct VideoObjectInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: VideoObjectParams

    var body: some View {
        Section("Video Layer") {
            Toggle(
                "Mirror horizontally",
                isOn: Binding(get: { params.mirror.horizontal }, set: { v in update { $0.mirror.horizontal = v } }))
            Toggle(
                "Mirror vertically",
                isOn: Binding(get: { params.mirror.vertical }, set: { v in update { $0.mirror.vertical = v } }))
            Toggle(
                "Red channel",
                isOn: Binding(get: { params.channelMask.red }, set: { v in update { $0.channelMask.red = v } }))
            Toggle(
                "Green channel",
                isOn: Binding(get: { params.channelMask.green }, set: { v in update { $0.channelMask.green = v } }))
            Toggle(
                "Blue channel",
                isOn: Binding(get: { params.channelMask.blue }, set: { v in update { $0.channelMask.blue = v } }))
        }
    }

    func update(_ change: (inout VideoObjectParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Video Layer") { $0.kind = .video(new) }
    }
}

struct ShapeInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: ShapeParams

    var body: some View {
        Section("Shape") {
            Picker("Shape", selection: Binding(get: { params.shape }, set: { v in update { $0.shape = v } })) {
                Text("Rectangle").tag(ShapeKind.rectangle)
                Text("Rounded rectangle").tag(ShapeKind.roundedRectangle)
                Text("Ellipse").tag(ShapeKind.ellipse)
            }
            ColorPicker(
                "Fill",
                selection: Binding(
                    get: { Color(params.fillColor) }, set: { c in update { $0.fillColor = RGBAColor(c) } }))
            Toggle(
                "Gradient fill",
                isOn: Binding(
                    get: { params.gradientEndColor != nil },
                    set: { on in
                        update { $0.gradientEndColor = on ? RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.75) : nil }
                    }))
            if let end = params.gradientEndColor {
                ColorPicker(
                    "Fades to",
                    selection: Binding(get: { Color(end) }, set: { c in update { $0.gradientEndColor = RGBAColor(c) } })
                )
                Toggle(
                    "Left to right",
                    isOn: Binding(
                        get: { params.gradientHorizontal }, set: { v in update { $0.gradientHorizontal = v } })
                )
            }
            ColorPicker(
                "Stroke",
                selection: Binding(
                    get: { Color(params.strokeColor) }, set: { c in update { $0.strokeColor = RGBAColor(c) } }))
            PercentSlider(
                "Stroke width",
                value: Binding(get: { params.strokeWidth }, set: { v in update { $0.strokeWidth = v } }),
                range: 0...0.05)
            if params.shape == .roundedRectangle {
                PercentSlider(
                    "Corner radius",
                    value: Binding(get: { params.cornerRadius }, set: { v in update { $0.cornerRadius = v } }),
                    range: 0...0.5)
            }
        }
    }

    func update(_ change: (inout ShapeParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Shape") { $0.kind = .shape(new) }
    }
}

struct TextInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: TextParams

    var body: some View {
        Section("Text") {
            CommittingTextField(
                "Text", text: Binding(get: { params.text }, set: { v in update { $0.text = v } }), axis: .vertical)
            PercentSlider(
                "Size", value: Binding(get: { params.fontScale }, set: { v in update { $0.fontScale = v } }),
                range: 0.1...1)
            Toggle("Bold", isOn: Binding(get: { params.bold }, set: { v in update { $0.bold = v } }))
            Picker(
                "Alignment", selection: Binding(get: { params.alignment }, set: { v in update { $0.alignment = v } })
            ) {
                Text("Leading").tag(ProjectModel.TextAlignment.leading)
                Text("Center").tag(ProjectModel.TextAlignment.center)
                Text("Trailing").tag(ProjectModel.TextAlignment.trailing)
            }
            ColorPicker(
                "Colour",
                selection: Binding(get: { Color(params.color) }, set: { c in update { $0.color = RGBAColor(c) } }))
            ColorPicker(
                "Background",
                selection: Binding(
                    get: { Color(params.backgroundColor) }, set: { c in update { $0.backgroundColor = RGBAColor(c) } }))
            PercentSlider(
                "Outline", value: Binding(get: { params.outlineWidth }, set: { v in update { $0.outlineWidth = v } }),
                range: 0...0.15)
            ColorPicker(
                "Outline colour",
                selection: Binding(
                    get: { Color(params.outlineColor) }, set: { c in update { $0.outlineColor = RGBAColor(c) } }))
        }
    }

    func update(_ change: (inout TextParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Text") { $0.kind = .text(new) }
    }
}

struct ImageObjectInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: ImageObjectParams

    var body: some View {
        Section("Image") {
            Picker(
                "Picture",
                selection: Binding(
                    get: { object.inputID },
                    set: { v in editor.updateObject(object.id, name: "Change Image") { $0.inputID = v } })
            ) {
                Text("None").tag(InputID?.none)
                ForEach(editor.project.inputs.filter(\.kind.isImage)) { Text($0.label).tag(InputID?.some($0.id)) }
            }
            Toggle(
                "Keep aspect ratio",
                isOn: Binding(get: { params.keepAspect }, set: { v in update { $0.keepAspect = v } }))
            NumberField(
                "Rotation (°)", value: Binding(get: { params.rotation }, set: { v in update { $0.rotation = v } }))
        }
        Section("Data-driven") {
            OptionalChannelPicker(
                editor: editor, title: "Rotate by channel",
                selection: Binding(get: { params.rotationChannel }, set: { v in update { $0.rotationChannel = v } }))
            if params.rotationChannel != nil {
                NumberField(
                    "Degrees per unit",
                    value: Binding(get: { params.degreesPerUnit }, set: { v in update { $0.degreesPerUnit = v } }))
            }
            OptionalChannelPicker(
                editor: editor, title: "Opacity from channel",
                selection: Binding(get: { params.opacityChannel }, set: { v in update { $0.opacityChannel = v } }))
            if params.opacityChannel != nil {
                NumberField(
                    "Opacity scale",
                    value: Binding(get: { params.opacityScale }, set: { v in update { $0.opacityScale = v } }))
            }
            OptionalChannelPicker(
                editor: editor, title: "Flash when channel above",
                selection: Binding(get: { params.flashChannel }, set: { v in update { $0.flashChannel = v } }))
            if params.flashChannel != nil {
                NumberField(
                    "Threshold",
                    value: Binding(get: { params.flashThreshold }, set: { v in update { $0.flashThreshold = v } }))
                NumberField(
                    "Flashes per second",
                    value: Binding(get: { params.flashHertz }, set: { v in update { $0.flashHertz = max(0.2, v) } }))
            }
        }
    }

    func update(_ change: (inout ImageObjectParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit Image") { $0.kind = .image(new) }
    }
}

/// Picks a channel from the first data input, or "None".
struct OptionalChannelPicker: View {
    let editor: EditorModel
    let title: String
    @Binding var selection: String?

    var body: some View {
        let session = editor.project.dataInputs.first.flatMap { editor.sessions[$0.id] }
        let available = session?.orderedChannels.map(\.role.identifier) ?? []
        Picker(title, selection: $selection) {
            Text("None").tag(String?.none)
            ForEach(available, id: \.self) { Text($0).tag(String?.some($0)) }
        }
    }
}

struct GForceInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GForceParams

    var body: some View {
        Section("G-Force") {
            NumberField("Max G", value: clamped(\.maxG, least: 0.5))
            NumberField("Trail (s)", value: clamped(\.trailSeconds, least: 0))
            Toggle("Show values", isOn: field(\.showValues))
        }
        Section("Lateral (left/right)") {
            axisPicker("Channel", selection: optional(\.lateralChannel), standard: "lateralG")
            Toggle("Invert", isOn: field(\.invertLateral))
        }
        Section("Longitudinal (braking/acceleration)") {
            axisPicker("Channel", selection: optional(\.longitudinalChannel), standard: "longitudinalG")
            Toggle("Invert", isOn: field(\.invertLongitudinal))
            Text(
                "Loggers disagree on which way is positive: RaceRender calls a right turn positive, "
                    + "ISO 8855 vehicle axes (which RaceChrono follows) call a left turn positive."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Lists the object's own data input, unlike `OptionalChannelPicker`, which always reads the
    /// project's first one. "Standard" leaves the channel empty so the axis follows its role.
    @ViewBuilder
    func axisPicker(_ title: String, selection: Binding<String?>, standard: String) -> some View {
        let session = object.inputID.flatMap { editor.sessions[$0] }
        let available = session?.orderedChannels.map(\.role.identifier) ?? []
        Picker(title, selection: selection) {
            Text("Standard (\(standard))").tag(String?.none)
            ForEach(available, id: \.self) { Text($0).tag(String?.some($0)) }
        }
        if let chosen = selection.wrappedValue, !available.isEmpty, !available.contains(chosen) {
            Label("\(chosen) is not in this data file.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.yellow)
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GForceParams, T>) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = v } })
    }

    func clamped(_ keyPath: WritableKeyPath<GForceParams, Double>, least: Double) -> Binding<Double> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update { $0[keyPath: keyPath] = max(least, v) } })
    }

    /// The pickers offer "None", which for these means "use the standard role for the axis".
    func optional(_ keyPath: WritableKeyPath<GForceParams, String>) -> Binding<String?> {
        Binding(
            get: { params[keyPath: keyPath].isEmpty ? nil : params[keyPath: keyPath] },
            set: { v in update { $0[keyPath: keyPath] = v ?? "" } })
    }

    func update(_ change: (inout GForceParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Edit G-Force") { $0.kind = .gForce(new) }
    }
}
