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
    /// One showing of the sheet. An import whose sheet comes back (#664) is shown under a new
    /// one, so the sheet is made afresh rather than taken up where a closed one left off.
    var id = UUID()
    /// The import, whichever showing of its sheet this is.
    let runID = UUID()
    let urls: [URL]
    var day: TrackDay?

    init(urls: [URL], day: TrackDay? = nil) {
        self.urls = urls
        self.day = day
    }

    func shownAgain() -> TrackDayRequest {
        var copy = self
        copy.id = UUID()
        return copy
    }
}

extension EditorModel {
    /// File ▸ Add Files to Logbook… with a project in front
    func requestTrackDay() {
        let urls = OpenPanels.chooseTrackDay()
        guard !urls.isEmpty else { return }
        trackDayRequest = TrackDayRequest(urls: urls)
    }
}

/// Enters a track day in the logbook and says what happened to each file (#346). With a day
/// chosen, files that are not from that day are read and kept back, and the sheet asks where they
/// go before anything is filed for them (#456). The import itself is a `TrackDayImportRun`, which
/// goes on when the sheet is sent away and brings it back at the end (#664).
struct TrackDayImportSheet: View {
    /// The front project, for its track library and status line; `nil` from the Logbook window
    /// with no project open.
    let editor: EditorModel?
    let request: TrackDayRequest
    /// The Logbook window's, when the sheet is on it: the files added are one step of its Undo,
    /// and the car set in the report another (#454). From a project's window, `nil` — the project's
    /// undo manager is the document's.
    var undo: UndoManager?
    /// The window the sheet is on.
    var home = TrackDayImportRun.Home.project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    private var runs = ImportRuns.shared
    /// The import, kept while the sheet leaves after Done has ended it.
    @State private var held: TrackDayImportRun?

    init(
        editor: EditorModel?, request: TrackDayRequest, undo: UndoManager? = nil,
        home: TrackDayImportRun.Home = .project
    ) {
        self.editor = editor
        self.request = request
        self.undo = undo
        self.home = home
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.day.map { "Add Sessions to \($0.label)" } ?? "Add Files to Logbook").font(.title2)
            if let run = held ?? runs.run(for: request) {
                TrackDayImportReport(run: run, day: request.day, show: { show($0, run) }, close: { dismiss() })
            } else {
                ProgressView("Looking for files…")
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { held = runs.begin(request, home: home, editor: editor, undo: undo) }
        // The window closed under the sheet, or it went some way that pressed no button.
        .onDisappear { (held ?? runs.run(for: request))?.sheetGone(request.id) }
    }

    /// The Logbook, brought forward, on the circuit's Trends or on the Season.
    private func show(_ destination: ImportProgress.Destination, _ run: TrackDayImportRun) {
        run.close()
        LogbookModel.shared.requestedView = destination
        openWindow(id: LogbookWindow.windowID)
        dismiss()
    }
}

/// What the sheet shows of its import: how far the reading has got, the question about files of
/// another day, then the report.
private struct TrackDayImportReport: View {
    @Bindable var run: TrackDayImportRun
    let day: TrackDay?
    let show: (ImportProgress.Destination) -> Void
    let close: () -> Void

    var body: some View {
        switch run.phase {
        case .waiting: ProgressView(run.activity.line)
        case .reading: reading
        case .asking: question
        case .placing: ProgressView(run.activity.line)
        case .done:
            Text(run.summary).accessibilityIdentifier("trackday.summary")
            progressLines
            goalLines
            if !run.carlessDays.isEmpty {
                ImportCarField(
                    days: run.carlessDays, knownCars: LogbookModel.shared.knownCars, car: $run.car,
                    carSet: run.carSet, set: run.setCar)
            }
        }
        List(Array(run.reports.enumerated()), id: \.offset) { _, report in
            Label(report.line, systemImage: symbol(for: report))
                .foregroundStyle(report.isAdded || report.isClip || report.isWaiting ? .primary : .secondary)
        }
        .frame(minHeight: 180)
        .accessibilityIdentifier("trackday.report")
        HStack {
            if run.phase == .asking {
                answers
            } else {
                Spacer()
                if run.phase == .done, let destination = run.progress.destination {
                    Button(destination.buttonTitle) { show(destination) }
                        .help(destination.help)
                        .accessibilityIdentifier("trackday.showProgress")
                }
                // While files are read this sends the sheet away and they go on being read: it
                // said Close, which said neither (#664).
                Button(run.activity.closeTitle) {
                    if run.phase == .done { run.close() } else { run.sendToBackground() }
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .help(
                    run.phase == .done
                        ? "" : "The files go on being read, and this report comes back when they are in"
                )
                .accessibilityIdentifier("trackday.done")
            }
        }
    }

    /// Which file of how many: the count is known as soon as the folders are listed, and a
    /// spinner beside one file's name for ten seconds said nothing of how far there was to go
    /// (#665).
    @ViewBuilder private var reading: some View {
        if let step = run.step {
            ProgressView(value: Double(step.index), total: Double(max(step.count, 1))) {
                Text(step.sentence).lineLimit(1).truncationMode(.middle)
            }
            .accessibilityIdentifier("trackday.reading")
        } else {
            ProgressView(run.activity.line)
        }
    }

    // MARK: - Progress (#459)

    /// A line for each goal the new sessions reached or brought closer.
    @ViewBuilder private var goalLines: some View {
        ForEach(run.goalNews) { news in
            Label {
                Text(news.sentence)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trackday.goal")
            } icon: {
                Image(systemName: news.reached ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(news.reached ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A line for each circuit the new sessions were driven at: the day's best against the visit
    /// before it.
    @ViewBuilder private var progressLines: some View {
        ForEach(run.progress.circuits) { circuit in
            Label {
                Text(circuit.sentence)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trackday.progress")
            } icon: {
                Image(systemName: circuit.isPersonalBest ? "trophy" : "flag.checkered")
                    .foregroundStyle(circuit.isPersonalBest ? Color.orange : Color.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func symbol(for report: TrackDayImport.Report) -> String {
        if report.isWaiting { return "calendar.badge.exclamationmark" }
        return report.isAdded ? "checkmark.circle" : report.isClip ? "video" : "minus.circle"
    }

    // MARK: - Files of another day (#456)

    /// The day the question is about: the one chosen before the files, else — a file dated away
    /// from the rest (#655) — the day the others went on.
    private var asked: TrackDay? { day ?? run.strays.first?.rest }

    /// How many are not the day's, and what can be done with them.
    private var question: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TrackDayImport.Stray.headline(run.strays.count, of: run.reports.count, day: asked?.label ?? ""))
                .font(.headline)
                .accessibilityIdentifier("trackday.strays.question")
            Text(TrackDayImport.Stray.explanation(run.strays.count, chosen: day != nil))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The three answers, the one that follows the files' own account as the default.
    @ViewBuilder private var answers: some View {
        let one = run.strays.count == 1
        Button(one ? "Leave It Out" : "Leave Them Out", role: .cancel) {
            run.finish()
            run.close()
            close()
        }
        .keyboardShortcut(.cancelAction)
        .help("The other files are in the logbook; \(one ? "this one is" : "these are") not added")
        .accessibilityIdentifier("trackday.strays.leaveOut")
        Spacer()
        Button(TrackDayImport.Stray.addTitle(chosen: day != nil)) { run.place(onto: asked) }
            .help(TrackDayImport.Stray.addHelp(chosen: day != nil))
            .accessibilityIdentifier("trackday.strays.thisDay")
        Button(one ? "Put on Its Own Day" : "Put on Their Own Days") { run.place(onto: nil) }
            .keyboardShortcut(.defaultAction)
            .help("Each goes on the day its own date and circuit say, made if there is none yet")
            .accessibilityIdentifier("trackday.strays.ownDays")
    }
}

extension ImportProgress.Destination {
    var buttonTitle: String {
        switch self {
        case .trends: "Show Trends"
        case .season: "Show Season"
        }
    }

    var help: String {
        switch self {
        case .trends(_, let title): "Open the Logbook on \(title)'s lap times across visits"
        case .season: "Open the Logbook on the season: days, circuits and personal bests"
        }
    }
}
