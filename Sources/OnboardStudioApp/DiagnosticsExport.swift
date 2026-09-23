import AppKit
import MediaKit
import ProjectModel
import TelemetryKit
import UniformTypeIdentifiers

/// Help ▸ Export Diagnostics… (#152): one zip a user can attach to a bug report. Nothing is sent
/// anywhere — the user chooses where it goes and whom to give it to — and it carries no media: the
/// project's settings with its file paths, a description of each data file, the app's log for this
/// launch, what it told the user, and any recent crash reports.
@MainActor
enum DiagnosticsExport {
    /// When this launch began, so the log is this launch's and not the whole day's.
    static let launchedAt = Date()

    static func run(editor: EditorModel?) {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let name = "Onboard Studio Diagnostics \(stamp).zip"
        guard let url = destination(suggestedName: name) else { return }
        do {
            try Diagnostics.writeBundle(files(editor: editor), to: url)
            editor?.statusMessage = "Saved \(url.lastPathComponent). Attach it to your bug report."
            if !UITestSupport.isActive { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch {
            let alert = NSAlert()
            alert.messageText = "The Diagnostics File Could Not Be Saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    static func files(editor: EditorModel?) -> [String: Data] {
        var files: [String: Data] = [:]
        files["about.txt"] = Data(about.utf8)
        files["log.txt"] = Data(Diagnostics.logText(since: launchedAt).utf8)
        if let editor {
            files["activity.txt"] = Data(editor.activity.text.utf8)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            files["project.json"] = try? encoder.encode(editor.project)
            for input in editor.project.dataInputs {
                guard let session = editor.sessions[input.id] else { continue }
                let importer = input.dataSettings?.importerID ?? "detected"
                let report = SessionReport(session: session, importer: importer)
                files["data/\(safe(input.label)).json"] = try? report.json()
            }
            let problems = editor.project.inputs.compactMap { input in
                editor.problems[input.id].map { "\(input.label): \($0)" }
            }
            if !problems.isEmpty { files["problems.txt"] = Data(problems.joined(separator: "\n").utf8) }
        }
        for report in Diagnostics.crashReports() {
            files["crashes/\(report.lastPathComponent)"] = try? Data(contentsOf: report)
        }
        return files
    }

    static var about: String {
        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return """
            Onboard Studio \(OnboardStudioVersion.marketing) (\(build))
            macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            Mac: \(hardwareModel)
            ffmpeg: \(FFmpegBridge.executable?.path(percentEncoded: false) ?? "not installed")
            Language: \(Locale.preferredLanguages.first ?? "?"), region: \(Locale.current.region?.identifier ?? "?")
            Written: \(Date().formatted(.iso8601))
            """
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    private static func safe(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private static func destination(suggestedName: String) -> URL? {
        if let directory = UITestSupport.exportDirectory { return directory.appending(path: suggestedName) }
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.message = "Nothing is sent anywhere. Attach the file to a bug report yourself."
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - After a crash

    private static let lastLaunchKey = "lastLaunchDate"

    /// Offers the bundle when the app crashed since it last started. Asked once per crash; never
    /// under the UI tests, where a crash of an earlier test must not put up a dialog.
    static func offerAfterCrash() {
        let defaults = UserDefaults.standard
        let lastLaunch = defaults.object(forKey: lastLaunchKey) as? Date
        defaults.set(Date(), forKey: lastLaunchKey)
        guard !UITestSupport.isActive, let lastLaunch,
            let crash = Diagnostics.crashReports().first,
            let date = try? crash.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            date > lastLaunch
        else { return }
        let alert = NSAlert()
        alert.messageText = "Onboard Studio Quit Unexpectedly"
        alert.informativeText =
            "A diagnostics file holds the crash report, the app's log and your project's settings — no "
            + "videos or data. Nothing is sent: you choose where to save it and whom to send it to."
        alert.addButton(withTitle: "Export Diagnostics…")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { run(editor: nil) }
    }
}
