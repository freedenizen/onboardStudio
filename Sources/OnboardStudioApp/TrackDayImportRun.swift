import MediaKit
import ProjectModel
import SwiftUI

/// One Add Files to Logbook…, from its files to its report. It is not the sheet's: the sheet can
/// be sent away with Continue in Background and the files go on being read, the Logbook window
/// says how far they have got, and the sheet comes back with the question or the report (#664).
/// It was the sheet's state, so closing the sheet left an import nobody could see and threw its
/// report away.
@MainActor @Observable final class TrackDayImportRun: Identifiable {
    /// The window the sheet is shown on, and comes back to.
    enum Home {
        case logbook
        case project
    }

    let request: TrackDayRequest
    let home: Home
    /// The project in front when the files were chosen, for its track library and status line.
    private(set) weak var editor: EditorModel?
    /// The Logbook window's, so the files added are one step of its Undo and the car another
    /// (#454); `nil` from a project's window, whose undo manager is the document's.
    let undo: UndoManager?
    private let tracks: TrackLibrary
    /// The logbook before the files went in.
    private var before: LogbookChange.Snapshot?

    private(set) var reports: [TrackDayImport.Report] = []
    /// How the new days compare with the visits before them (#459), once the sessions are in.
    private(set) var progress = ImportProgress(circuits: [])
    /// The goals the new sessions reached or brought closer (#461).
    private(set) var goalNews: [GoalNews] = []
    /// The days the new sessions went on with no car (#489), and the car the report gives them.
    private(set) var carlessDays: [TrackDay] = []
    var car = ""
    private(set) var carSet: String?
    /// The file being read, and how many there are (#665).
    private(set) var step: TrackDayImport.Step?
    private(set) var phase: TrackDayImport.Phase
    /// The sheet was sent away, or its window closed, with the import still to end.
    private(set) var isInBackground = false
    /// The showing of the sheet that is up, until a button of its own sends it away.
    @ObservationIgnored private var showing: UUID?

    var id: UUID { request.runID }
    var activity: TrackDayImport.Activity {
        TrackDayImport.Activity(phase: phase, step: step, isInBackground: isInBackground)
    }

    var strays: [TrackDayImport.Stray] {
        reports.compactMap { if case .waiting(let stray) = $0.outcome { stray } else { nil } }
    }

    var summary: String { TrackDayImport.summary(of: reports, onChosenDay: request.day != nil) }

    init(request: TrackDayRequest, home: Home, editor: EditorModel?, undo: UndoManager?, waits: Bool) {
        self.request = request
        self.home = home
        self.editor = editor
        self.undo = undo
        tracks = editor?.trackLibrary ?? TrackLibrary.app
        phase = waits ? .waiting : .reading
    }

    // MARK: - Reading

    /// Reads the files and files them, as far as the question or the report.
    func read() async {
        phase = .reading
        if undo != nil { before = AppLogbook.shared.snapshot() }
        if let delay = UITestSupport.importDelay { try? await Task.sleep(for: delay) }
        let urls = request.urls
        let day = request.day
        let logbook = AppLogbook.shared
        let tracks = tracks
        let reading: @Sendable (Int, Int, URL) -> Void = { [weak self] index, count, url in
            Task { @MainActor in
                self?.step = TrackDayImport.Step(index: index, count: count, name: url.lastPathComponent)
            }
        }
        let result = await Task.detached(priority: .userInitiated) {
            // A file that is not from the chosen day waits for the question, rather than going on
            // the day whatever it says (#456).
            await TrackDayImport.run(urls, into: logbook, tracks: tracks, day: day, strays: .kept, progress: reading)
        }.value
        reports = result
        if strays.isEmpty {
            finish()
        } else {
            phase = .asking
            LogbookModel.shared.reload()
            ImportRuns.shared.surface()
        }
    }

    /// Files the waiting files where the user said, each line taking its file's place in the list.
    func place(onto day: TrackDay?) {
        let waiting = strays
        let logbook = AppLogbook.shared
        let tracks = tracks
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

    func finish() {
        phase = .done
        // A recording read as a session of its own is one of them (#665): it was left out of the
        // count, and of the progress, the goals and the question about the car with it.
        let ids = reports.compactMap(\.addedEntry?.id)
        editor?.statusMessage = "Added \(ids.count) session\(ids.count == 1 ? "" : "s") to the logbook."
        let model = LogbookModel.shared
        model.reload()
        if let before { model.record("Add Files", since: before, undo: undo) }
        progress = ImportProgress.make(added: Set(ids), in: model.entries)
        goalNews = GoalNews.make(
            goals: model.goals, added: Set(ids), in: model.entries, speed: LogbookWindow.speedUnit)
        carlessDays = Garage.daysWithoutCar(added: Set(ids), entries: model.entries, days: model.days)
        ImportRuns.shared.surface()
    }

    /// The car typed in the report goes on the days that had none, once — on Set Car or Return,
    /// else as the report is closed, so a car typed and not set is not lost.
    func setCar() {
        let name = car.trimmingCharacters(in: .whitespaces)
        guard carSet == nil, !name.isEmpty, !carlessDays.isEmpty else { return }
        LogbookModel.shared.setCar(name, onDays: carlessDays.map(\.id), undo: undo)
        carSet = name
    }

    // MARK: - The sheet

    /// Puts the sheet on its window, unless that window is showing another import's: then this
    /// one waits its turn. From a project that has since closed, the Logbook window has it.
    /// `unasked` is the sheet coming back by itself, which waits for any other sheet on the
    /// window to go — a day being typed is not covered by a report.
    @discardableResult func showSheet(unasked: Bool = false) -> Bool {
        if unasked, homeWindow?.attachedSheet != nil { return false }
        if home == .project, let editor {
            guard editor.trackDayRequest == nil else { return editor.trackDayRequest?.runID == id }
            editor.trackDayRequest = request.shownAgain()
            return true
        }
        let model = LogbookModel.shared
        guard model.trackDayRequest == nil else { return model.trackDayRequest?.runID == id }
        model.trackDayRequest = request.shownAgain()
        return true
    }

    private var homeWindow: NSWindow? {
        if home == .project, let editor { return editor.window }
        return NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(LogbookWindow.windowID) == true }
    }

    /// A sheet showing this import is up.
    func sheetShown(_ shown: UUID) {
        showing = shown
        isInBackground = false
    }

    /// Continue in Background: the sheet goes and the files go on being read.
    func sendToBackground() {
        showing = nil
        isInBackground = true
        if home == .project { editor?.statusMessage = TrackDayImport.Activity.sentToBackground }
    }

    /// Done, with the report read: the import is over.
    func close() {
        showing = nil
        setCar()
        ImportRuns.shared.forget(self)
    }

    /// A sheet went with none of its buttons pressed — its window closed. With the report up
    /// that is Done; before it, the import goes on unseen. A sheet a button sent away is not the
    /// one showing any more, so its going, which can be reported late, changes nothing.
    func sheetGone(_ shown: UUID) {
        guard showing == shown else { return }
        if phase == .done {
            close()
        } else {
            sendToBackground()
            Task { ImportRuns.shared.surface() }
        }
    }
}

/// Every import that has not been read to its end. They are read one after another: two at once
/// could each find the same file new and add it twice.
@MainActor @Observable final class ImportRuns {
    static let shared = ImportRuns()

    private(set) var runs: [TrackDayImportRun] = []
    /// The reading of the import begun last, which the next one waits for.
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// A sheet leaving a window is when a report that waited for it can be shown.
    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndSheetNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in ImportRuns.shared.surface() }
        }
    }

    /// The imports whose sheets are away, the oldest first.
    var inBackground: [TrackDayImportRun] { runs.filter(\.isInBackground) }

    func run(for request: TrackDayRequest) -> TrackDayImportRun? { runs.first { $0.id == request.runID } }

    /// The run of a sheet that has just been shown: begun, or — a sheet come back — taken up
    /// where it is.
    func begin(
        _ request: TrackDayRequest, home: TrackDayImportRun.Home, editor: EditorModel?, undo: UndoManager?
    ) -> TrackDayImportRun {
        if let run = run(for: request) {
            run.sheetShown(request.id)
            return run
        }
        let previous = runs.contains { $0.phase == .waiting || $0.phase == .reading } ? reading : nil
        let run = TrackDayImportRun(
            request: request, home: home, editor: editor, undo: undo, waits: previous != nil)
        run.sheetShown(request.id)
        runs.append(run)
        reading = Task {
            await previous?.value
            await run.read()
        }
        return run
    }

    func forget(_ run: TrackDayImportRun) {
        runs.removeAll { $0.id == run.id }
    }

    /// Brings back the sheet of each import that has a question or its report, where its window
    /// is free to show it. Called when an import reaches either, and when a sheet has gone.
    /// Until then the Logbook's bar says the files are in, with a button for the report.
    func surface() {
        for run in runs where run.activity.wantsItsSheet { run.showSheet(unasked: true) }
    }
}
