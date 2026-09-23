import ProjectModel
import SwiftUI

/// Project ▸ Save as Template… (#44): a name, and a picture of the layout that will be saved, so
/// what goes into the template is seen rather than described.
struct SaveTemplateSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var template: ProjectTemplate?

    var cleanedName: String { TemplateLibrary.cleaned(name) }
    var replaces: Bool { TemplateLibrary.app.entry(named: cleanedName) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as Template").font(.title2)
            Text(
                "The layout is saved: objects, fonts, segments, output size and export settings. Videos, data "
                    + "files and the project's details stay with this project."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TemplatePicture(template: template, width: 340).frame(maxWidth: .infinity)
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("saveTemplate.name")
                    .onSubmit(save)
            }
            if replaces {
                Label(
                    "You already have a template called “\(cleanedName)”. Saving replaces it.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(replaces ? "Replace" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanedName.isEmpty)
                    .accessibilityIdentifier("saveTemplate.save")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            let suggested = editor.fileURL?.deletingPathExtension().lastPathComponent ?? "My Template"
            name = TemplateLibrary.app.availableName(suggested)
            template = ProjectTemplate(name: suggested, project: editor.project)
        }
    }

    /// Reads the name when Return is pressed, not when the view last drew (see #74's popover).
    func save() {
        let name = cleanedName
        guard !name.isEmpty else { return }
        editor.saveTemplate(named: name)
        dismiss()
    }
}
