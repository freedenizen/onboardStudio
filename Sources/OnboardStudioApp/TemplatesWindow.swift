import AppKit
import ProjectModel
import SwiftUI

/// Every template with a picture of its layout (#44, #395): the built-in ones and yours. Click
/// one to start a project with it; right-click one of yours to rename, duplicate, show, export
/// or delete it. Once the welcome window; since the Logbook opens at launch, a window of its own.
struct TemplatesWindow: View {
    static let windowID = "templates"

    @State private var userTemplates: [TemplateLibrary.Entry] = []
    @State private var renaming: TemplateLibrary.Entry?
    @State private var deleting: TemplateLibrary.Entry?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Click a template to start a project with its layout. Right-click one of yours to manage it.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Built In").font(.headline)
                grid(
                    ProjectTemplate.builtIn.map {
                        Card(name: $0.name, detail: "\($0.displayObjects.count) objects", template: $0)
                    })
                if !userTemplates.isEmpty {
                    Text("Yours").font(.headline).padding(.top, 4)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 144), spacing: 10)], alignment: .leading, spacing: 10
                    ) {
                        ForEach(userTemplates) { entry in userCard(entry) }
                    }
                }
                Text("File ▸ Import Template… adds one someone sent you; Project ▸ Save as Template… keeps your own.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 640, minHeight: 360)
        .onReceive(NotificationCenter.default.publisher(for: .templatesChanged)) { _ in
            userTemplates = TemplateLibrary.app.entries()
        }
        .onAppear { userTemplates = TemplateLibrary.app.entries() }
        .confirmationDialog(
            "Delete the template “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { entry in
            Button("Move to Trash", role: .destructive) { perform { try TemplateLibrary.app.remove(entry) } }
        } message: { _ in
            Text("It moves to the Trash, where you can put it back.")
        }
        .alert(
            "Problem", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("OK") { failure = nil }
        } message: {
            Text($0)
        }
    }

    private struct Card {
        let name: String
        let detail: String
        let template: ProjectTemplate
    }

    private func grid(_ cards: [Card]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(cards, id: \.name) { card in
                TemplateCard(name: card.name, detail: card.detail, template: card.template) { start(card.template) }
                    .accessibilityIdentifier("launcher.template.\(card.name)")
            }
        }
    }

    /// One of the user's own templates, with what can be done to it on a right-click (#44).
    private func userCard(_ entry: TemplateLibrary.Entry) -> some View {
        let template = try? TemplateLibrary.app.load(entry)
        return TemplateCard(name: entry.name, detail: "Your template", template: template) {
            if let template { start(template) } else { failure = "“\(entry.name)” could not be read as a template." }
        }
        .accessibilityIdentifier("launcher.template.\(entry.name)")
        .contextMenu {
            Button("Rename…") { renaming = entry }
            Button("Duplicate") { perform { try TemplateLibrary.app.duplicate(entry) } }
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button("Export…") {
                guard let url = OpenPanels.chooseTemplateDestination(suggestedName: entry.name) else { return }
                perform { try TemplateLibrary.app.export(entry, to: url) }
            }
            Divider()
            Button("Delete…") { deleting = entry }
        }
        .popover(
            isPresented: Binding(get: { renaming == entry }, set: { if !$0 { renaming = nil } }), arrowEdge: .bottom
        ) {
            RenameTemplatePopover(name: entry.name) { newName in
                perform { try TemplateLibrary.app.rename(entry, to: newName) }
                renaming = nil
            } cancel: {
                renaming = nil
            }
        }
    }

    /// Runs a change to the library, refreshes every list of templates and says what went wrong.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch let error as TemplateLibraryError {
            failure = error.description
        } catch {
            failure = error.localizedDescription
        }
        NotificationCenter.default.post(name: .templatesChanged, object: nil)
    }

    private func start(_ template: ProjectTemplate) {
        // The new window's editor picks the template up when it appears.
        PendingTemplate.shared.template = template
        NSDocumentController.shared.newDocument(nil)
    }
}

private struct TemplateCard: View {
    let name: String
    let detail: String
    let template: ProjectTemplate?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                TemplatePicture(template: template, width: 128)
                Text(name).font(.callout).bold().lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 128, alignment: .leading).padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(detail)")
    }
}

/// Renames one of the user's templates in place, as a Finder rename would.
private struct RenameTemplatePopover: View {
    @State var name: String
    let rename: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .accessibilityIdentifier("launcher.renameTemplate")
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Rename", action: commit).keyboardShortcut(.defaultAction)
                    .disabled(TemplateLibrary.cleaned(name).isEmpty)
            }
        }
        .padding()
        .frame(width: 260)
    }

    /// Reads the name when Return is pressed, not when the view last drew.
    func commit() {
        guard !TemplateLibrary.cleaned(name).isEmpty else { return }
        rename(name)
    }
}
