import AppKit
import ProjectModel
import SwiftUI

/// What the app does when it starts with no project to restore.
enum LaunchOptions {
    /// The welcome window unless the user turned it off (then a blank project opens instead).
    /// The UI tests pass `-skipLauncher YES` to start on a blank project; that is a launch
    /// argument rather than a setting, so it is not one of the `Preferences`.
    static var showLauncher: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "skipLauncher") { return false }
        return defaults.value(for: Preferences.showLauncherAtLaunch)
    }

    /// Set once the welcome window has made its launch-time decision.
    @MainActor static var launchHandled = false

    /// Without this, a document-based app shows a bare Open panel at launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// With the welcome window there is no untitled project until the user asks for one.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !LaunchOptions.showLauncher }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = DiagnosticsExport.launchedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { DiagnosticsExport.offerAfterCrash() }
    }

    /// Files opened from the Finder. A template is not a document: opening one adds it to the
    /// user's templates (#44). Everything else goes to the document controller, which is where
    /// AppKit sends files when a delegate does not take them.
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        let extensions = [ProjectTemplate.fileExtension, ProjectTemplate.legacyFileExtension]
        let templates = urls.filter { extensions.contains($0.pathExtension.lowercased()) }
        for url in urls where !templates.contains(url) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSAlert(error: error).runModal() }
            }
        }
        if !templates.isEmpty { TemplateImport.add(templates) }
    }
}

/// The welcome window: a blank project, a project from a template, or an existing project.
struct LauncherView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Preferences.showLauncherAtLaunch.key) private var showAtLaunch = Preferences
        .showLauncherAtLaunch.unset
    @State private var recents: [URL] = []
    @State private var userTemplates: [TemplateLibrary.Entry] = []
    @State private var renaming: TemplateLibrary.Entry?
    @State private var deleting: TemplateLibrary.Entry?
    @State private var failure: String?

    var body: some View {
        HStack(spacing: 0) {
            identity.frame(width: 250).frame(maxHeight: .infinity).background(.quaternary.opacity(0.4))
            choices.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 480)
        .onReceive(NotificationCenter.default.publisher(for: .templatesChanged)) { _ in
            userTemplates = TemplateLibrary.app.entries()
        }
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
        .onAppear {
            recents = NSDocumentController.shared.recentDocumentURLs.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            userTemplates = TemplateLibrary.app.entries()
            // Projects restored from the last session make the welcome window unnecessary, but only
            // at launch: opened from the Help menu it stays whatever else is open.
            guard !LaunchOptions.launchHandled else { return }
            LaunchOptions.launchHandled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !NSDocumentController.shared.documents.isEmpty { dismissWindow(id: "launcher") }
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text("Onboard Studio").font(.largeTitle).bold()
            Text("Version \(OnboardStudioVersion.marketing)").foregroundStyle(.secondary)
            Text("Lap video and data in, overlay video out.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 16)
            Spacer()
            Toggle("Show this window at launch", isOn: $showAtLaunch)
                .toggleStyle(.checkbox).font(.callout).padding(.bottom, 14)
                .accessibilityIdentifier("launcher.showAtLaunch")
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start a project").font(.title2).bold()
            HStack(spacing: 12) {
                LauncherButton(title: "New Blank Project", symbol: "doc.badge.plus", prominent: true) {
                    start { NSDocumentController.shared.newDocument(nil) }
                }
                .accessibilityIdentifier("launcher.newBlank")
                LauncherButton(title: "Open Project…", symbol: "folder") {
                    NSDocumentController.shared.openDocument(nil)
                }
                .accessibilityIdentifier("launcher.open")
            }
            Text("From a template").font(.headline).padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ProjectTemplate.builtIn, id: \.name) { template in
                        TemplateCard(
                            name: template.name, detail: "\(template.displayObjects.count) objects", template: template
                        ) {
                            start(template)
                        }
                        .accessibilityIdentifier("launcher.template.\(template.name)")
                    }
                    ForEach(userTemplates) { entry in userCard(entry) }
                }
            }
            HStack {
                Text("Recent projects").font(.headline)
                Spacer()
                Button("Open the Sample Project") {
                    SampleProject.open()
                    dismissWindow(id: "launcher")
                }
                .buttonStyle(.link).disabled(!SampleProject.isAvailable)
                .accessibilityIdentifier("launcher.sample")
            }
            .padding(.top, 4)
            if recents.isEmpty {
                Text("Projects you save appear here.").foregroundStyle(.secondary).font(.callout)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(recents.prefix(8), id: \.self) { url in
                            Button {
                                start {
                                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) {
                                        _, _, error in
                                        if let error { NSAlert(error: error).runModal() }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.richtext").accessibilityHidden(true)
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Spacer()
                                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                        .foregroundStyle(.secondary).font(.caption).lineLimit(1).truncationMode(.head)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.vertical, 3)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
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
        start {
            // The new window's editor picks the template up when it appears.
            PendingTemplate.shared.template = template
            NSDocumentController.shared.newDocument(nil)
        }
    }

    private func start(_ action: () -> Void) {
        action()
        dismissWindow(id: "launcher")
    }
}

private struct LauncherButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .controlSize(.large)
        .modifier(Prominence(prominent: prominent))
    }

    private struct Prominence: ViewModifier {
        let prominent: Bool
        func body(content: Content) -> some View {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
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
