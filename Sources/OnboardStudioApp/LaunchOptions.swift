import AppKit
import ProjectModel

/// What the app does when it starts with no project to restore (#395).
enum LaunchOptions {
    /// The Logbook unless the user turned it off (then a blank project opens instead).
    /// The UI tests pass `-skipLogbook YES` to start on a blank project; that is a launch
    /// argument rather than a setting, so it is not one of the `Preferences`.
    static var openLogbook: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "skipLogbook") { return false }
        return defaults.value(for: Preferences.openLogbookAtLaunch)
    }

    /// Without this, a document-based app shows a bare Open panel at launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// With the Logbook at launch there is no untitled project until the user asks for one.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !LaunchOptions.openLogbook }

    /// Before any document opens, restored or from the Finder: edits wait for File ▸ Save (#300).
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { ManualSaving.install() }
    }

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
