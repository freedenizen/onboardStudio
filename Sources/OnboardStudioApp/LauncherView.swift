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
}

/// The welcome window: a blank project, a project from a template, or an existing project.
struct LauncherView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Preferences.showLauncherAtLaunch.key) private var showAtLaunch = Preferences
        .showLauncherAtLaunch.unset
    @State private var recents: [URL] = []
    @State private var userTemplates: [TemplateStore.Entry] = []

    var body: some View {
        HStack(spacing: 0) {
            identity.frame(width: 250).frame(maxHeight: .infinity).background(.quaternary.opacity(0.4))
            choices.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 440)
        .onAppear {
            recents = NSDocumentController.shared.recentDocumentURLs.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            userTemplates = TemplateStore.userTemplates()
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
                HStack(spacing: 10) {
                    ForEach(ProjectTemplate.builtIn, id: \.name) { template in
                        TemplateCard(name: template.name, detail: "\(template.displayObjects.count) objects") {
                            start(template)
                        }
                        .accessibilityIdentifier("launcher.template.\(template.name)")
                    }
                    ForEach(userTemplates) { entry in
                        TemplateCard(name: entry.name, detail: "Your template") {
                            if let template = try? TemplateStore.load(entry.url) { start(template) }
                        }
                    }
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
                                    Image(systemName: "doc.richtext")
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.67percent").font(.title2).foregroundStyle(.tint)
                Text(name).font(.callout).bold().lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 118, alignment: .leading).padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
