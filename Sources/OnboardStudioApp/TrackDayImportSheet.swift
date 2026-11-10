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

/// Enters a track day in the logbook and says what happened to each file (#346). With a day
/// chosen, files that are not from that day are read and kept back, and the sheet asks where they
/// go before anything is filed for them (#456).
struct TrackDayImportSheet: View {
    /// The front project, for its track library and status line; `nil` from the Logbook window
    /// with no project open.
    let editor: EditorModel?
    let request: TrackDayRequest
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [TrackDayImport.Report] = []
    @State private var current: String?
    @State private var phase = Phase.reading

    private enum Phase {
        case reading
        /// Files of another day are waiting to be told where they go.
        case asking
        case placing
        case done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.day.map { "Add Sessions to \($0.label)" } ?? "Add Track Day to Logbook").font(.title2)
            switch phase {
            case .reading: ProgressView(current.map { "Reading \($0)…" } ?? "Looking for files…")
            case .asking: question
            case .placing: ProgressView("Adding…")
            case .done: Text(summary).accessibilityIdentifier("trackday.summary")
            }
            List(Array(reports.enumerated()), id: \.offset) { _, report in
                Label(report.line, systemImage: symbol(for: report))
                    .foregroundStyle(report.isAdded || report.isClip || report.isWaiting ? .primary : .secondary)
            }
            .frame(minHeight: 180)
            .accessibilityIdentifier("trackday.report")
            HStack {
                if phase == .asking {
                    answers
                } else {
                    Spacer()
                    Button(phase == .done ? "Done" : "Close") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(phase == .placing)
                        .accessibilityIdentifier("trackday.done")
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await run() }
    }

    private func symbol(for report: TrackDayImport.Report) -> String {
        if report.isWaiting { return "calendar.badge.exclamationmark" }
        return report.isAdded ? "checkmark.circle" : report.isClip ? "video" : "minus.circle"
    }

    // MARK: - Files of another day (#456)

    private var strays: [TrackDayImport.Stray] {
        reports.compactMap { if case .waiting(let stray) = $0.outcome { stray } else { nil } }
    }

    /// How many are not the day's, and what can be done with them.
    private var question: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TrackDayImport.Stray.headline(strays.count, of: reports.count, day: request.day?.label ?? ""))
                .font(.headline)
                .accessibilityIdentifier("trackday.strays.question")
            Text(TrackDayImport.Stray.explanation(strays.count))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The three answers, the one that follows the files' own account as the default.
    @ViewBuilder private var answers: some View {
        let one = strays.count == 1
        Button(one ? "Leave It Out" : "Leave Them Out", role: .cancel) {
            finish()
            dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .help("The other files are in the logbook; \(one ? "this one is" : "these are") not added")
        .accessibilityIdentifier("trackday.strays.leaveOut")
        Spacer()
        Button("Add to This Day") { place(onto: request.day) }
            .help("For a logger or camera whose clock was wrong: the day you chose decides")
            .accessibilityIdentifier("trackday.strays.thisDay")
        Button(one ? "Put on Its Own Day" : "Put on Their Own Days") { place(onto: nil) }
            .keyboardShortcut(.defaultAction)
            .help("Each goes on the day its own date and circuit say, made if there is none yet")
            .accessibilityIdentifier("trackday.strays.ownDays")
    }

    /// Files the waiting files where the user said, each line taking its file's place in the list.
    private func place(onto day: TrackDay?) {
        let waiting = strays
        let logbook = AppLogbook.shared
        let tracks = editor?.trackLibrary ?? TrackLibrary()
        phase = .placing
        Task {
            let placed = await Task.detached(priority: .userInitiated) {
                TrackDayImport.place(waiting, onto: day, into: logbook, tracks: tracks)
            }.value
            let lines = Dictionary(placed.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            reports = reports.map { report in report.isWaiting ? lines[report.url] ?? report : report }
            finish()
        }
    }

    // MARK: - Reading

    private var summary: String {
        let added = reports.filter(\.isAdded).count
        let skipped = reports.filter(\.isAlreadyThere).count
        let clips = reports.filter(\.isClip).count
        var parts = ["\(added) session\(added == 1 ? "" : "s") added"]
        // With a day chosen, a session that went elsewhere is said to have (#456).
        let elsewhere = request.day == nil ? 0 : reports.filter { $0.isAdded && $0.dayLabel != nil }.count
        if elsewhere > 0 {
            let days = elsewhere == 1 ? "its own day" : "their own days"
            parts.append(elsewhere == added ? "on \(days)" : "\(elsewhere) of them on \(days)")
        }
        if clips > 0 { parts.append("\(clips) clip\(clips == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) already in the logbook") }
        let rest = reports.count - added - skipped - clips
        if rest > 0 { parts.append("\(rest) not read") }
        return reports.isEmpty ? "Nothing in those files that this app reads." : parts.joined(separator: ", ") + "."
    }

    private func run() async {
        let urls = request.urls
        let day = request.day
        let logbook = AppLogbook.shared
        let tracks = editor?.trackLibrary ?? TrackLibrary()
        let result = await Task.detached(priority: .userInitiated) {
            // A file that is not from the chosen day waits for the question, rather than going on
            // the day whatever it says (#456).
            await TrackDayImport.run(urls, into: logbook, tracks: tracks, day: day, strays: .kept) { _, _, url in
                Task { @MainActor in current = url.lastPathComponent }
            }
        }.value
        reports = result
        if strays.isEmpty {
            finish()
        } else {
            phase = .asking
            LogbookModel.shared.reload()
        }
    }

    private func finish() {
        phase = .done
        let added = reports.filter(\.isAdded).count
        editor?.statusMessage = "Added \(added) session\(added == 1 ? "" : "s") to the logbook."
        LogbookModel.shared.reload()
    }
}
