import ProjectModel
import RenderKit
import SwiftUI

/// The font text is drawn in (#118): one object's, or the project's for every object that has not
/// chosen its own. A family pop-up and a typeface pop-up, as the Font panel and Pages lay them out,
/// with the inherited choice first and named for what it resolves to.
struct FontSection: View {
    /// The installed families, read once: the list is long and asking the font server for it on
    /// every redraw of the inspector would be felt.
    static let families = Typefaces.families()

    let typeface: Typeface?
    /// What choosing nothing means here, as the pop-up says it: `Project Font (Futura Medium)`.
    let inherited: String
    /// The face a newly picked family starts in when there is no face of this level's own to keep.
    let inheritedFace: String?
    /// Says what happens to text while `typeface` is not installed.
    let missingNote: String
    let identifier: String
    let set: (Typeface?, String) -> Void
    var textScale: Binding<Double>?
    var caption: String?

    var body: some View {
        Section("Font") {
            Picker("Font", selection: familyBinding) {
                Text(inherited).tag(String?.none)
                Divider()
                if let family = typeface?.family, !Self.families.contains(family) {
                    Text("\(family) (Missing)").tag(String?.some(family))
                }
                ForEach(Self.families, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .accessibilityIdentifier("\(identifier).family")
            if let typeface {
                Picker("Typeface", selection: faceBinding) {
                    if !faces.contains(typeface.face) {
                        Text("\(typeface.face) (Missing)").tag(typeface.face)
                    }
                    ForEach(faces, id: \.self) { Text($0).tag($0) }
                }
                .accessibilityIdentifier("\(identifier).face")
                if !Typefaces.isInstalled(typeface) {
                    Label(
                        "\(typeface.displayName) is not installed on this Mac. \(missingNote)",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let textScale {
                SliderField(
                    "Text size", value: textScale, in: TextScale.range, scale: .percent, unit: "%",
                    identifier: "\(identifier).size")
            }
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var faces: [String] { typeface.map { Typefaces.faces(of: $0.family) } ?? [] }

    var familyBinding: Binding<String?> {
        Binding(
            get: { typeface?.family },
            set: { family in
                guard let family else { return set(nil, "Font") }
                let face = Typefaces.face(for: family, keeping: typeface?.face ?? inheritedFace) ?? "Regular"
                set(Typeface(family: family, face: face), "Font")
            })
    }

    var faceBinding: Binding<String> {
        Binding(
            get: { typeface?.face ?? "" },
            set: { face in
                guard let family = typeface?.family else { return }
                set(Typeface(family: family, face: face), "Typeface")
            })
    }
}

/// An object's font: its own, or the project's, or failing both the fonts it draws in by itself.
/// Nothing at all for an object that draws no text.
struct ObjectFontSection: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject

    var body: some View {
        if object.kind.drawsText { section }
    }

    var section: some View {
        let project = editor.project.settings.typeface
        return FontSection(
            typeface: object.typeface,
            inherited: project.map { "Project Font (\($0.displayName))" } ?? builtIn,
            inheritedFace: project?.face,
            missingNote: "This object draws in its built-in fonts until it is.",
            identifier: "object.font",
            set: { typeface, name in
                editor.updateObject(object.id, name: "Change \(name)") { $0.typeface = typeface }
            },
            textScale: object.kind.sizesOwnText
                ? nil
                : Binding(
                    get: { object.textScale ?? 1 },
                    set: { value in editor.updateObject(object.id, name: "Change Text Size") { $0.textScale = value } })
        )
    }

    /// The font an object draws in without a choice. Text objects carry one of their own; every
    /// other object draws labels in Helvetica Neue and numbers in Menlo.
    var builtIn: String {
        switch object.kind {
        case .text(let params): "Built-In (\(params.fontName)\(params.bold ? " Bold" : ""))"
        case .textData(let params): "Built-In (\(params.fontName.isEmpty ? "Menlo" : params.fontName))"
        default: "Built-In"
        }
    }
}

/// The project's font, for every object that has not chosen its own.
struct ProjectFontSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        FontSection(
            typeface: editor.project.settings.typeface,
            inherited: "Built-In",
            inheritedFace: nil,
            missingNote: "Objects draw in their built-in fonts until it is.",
            identifier: "project.font",
            set: { typeface, name in editor.edit("Change Project \(name)") { $0.settings.typeface = typeface } },
            caption: "For every object in this project that has not chosen its own. Built-In draws labels in "
                + "Helvetica Neue and numbers in Menlo.")
    }
}
