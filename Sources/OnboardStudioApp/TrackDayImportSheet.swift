import MediaKit
import ProjectModel
import SwiftUI

/// What the app's logbook is: the user's, or a scratch one under UI tests.
enum AppLogbook {
    static var shared: Logbook { Logbook(directory: UITestSupport.logbookDirectory) }
}

/// The files and folders of one Add Track Day… (#346), and the day they go on when one was
/// chosen (#393) — else each file goes on the day its date and circuit say.
struct TrackDayRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    var day: TrackDay?
}

extension EditorModel {
    /// File ▸ Add Track Day to Logbook…
    func requestTrackDay() {
        let urls = OpenPanels.chooseTrackDay()
        guard !urls.isEmpty else { return }
        trackDayRequest = TrackDayRequest(urls: urls)
    }
}

/// Enters a track day in the logbook and says what happened to each file (#346).
struct TrackDayImportSheet: View {
    /// The front project, for its track library and status line; `nil` from the Logbook window
    /// with no project open.
    let editor: EditorModel?
    let request: TrackDayRequest
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [TrackDayImport.Report] = []
    @State private var current: String?
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.day.map { "Add Sessions to \($0.label)" } ?? "Add Track Day to Logbook").font(.title2)
            if done {
                Text(summary).accessibilityIdentifier("trackday.summary")
            } else {
                ProgressView(current.map { "Reading \($0)…" } ?? "Looking for files…")
            }
            List(Array(reports.enumerated()), id: \.offset) { _, report in
                Label(report.line, systemImage: report.isAdded ? "checkmark.circle" : "minus.circle")
                    .foregroundStyle(report.isAdded ? .primary : .secondary)
            }
            .frame(minHeight: 180)
            .accessibilityIdentifier("trackday.report")
            HStack {
                Spacer()
                Button(done ? "Done" : "Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("trackday.done")
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await run() }
    }

    private var summary: String {
        let added = reports.filter(\.isAdded).count
        let skipped = reports.filter { if case .alreadyThere = $0.outcome { return true } else { return false } }.count
        var parts = ["\(added) session\(added == 1 ? "" : "s") added"]
        if skipped > 0 { parts.append("\(skipped) already in the logbook") }
        let rest = reports.count - added - skipped
        if rest > 0 { parts.append("\(rest) not read") }
        return reports.isEmpty ? "Nothing in those files that this app reads." : parts.joined(separator: ", ") + "."
    }

    private func run() async {
        let urls = request.urls
        let day = request.day
        let logbook = AppLogbook.shared
        let tracks = editor?.trackLibrary ?? TrackLibrary()
        let result = await Task.detached(priority: .userInitiated) {
            await TrackDayImport.run(urls, into: logbook, tracks: tracks, day: day) { _, _, url in
                Task { @MainActor in current = url.lastPathComponent }
            }
        }.value
        reports = result
        done = true
        let added = result.filter(\.isAdded).count
        editor?.statusMessage = "Added \(added) session\(added == 1 ? "" : "s") to the logbook."
        LogbookModel.shared.reload()
    }
}
