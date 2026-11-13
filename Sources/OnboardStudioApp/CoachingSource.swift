import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// What the Coaching window reads (#396): the front project's lap, as it always has, or one
/// logbook session with no project open at all.
enum CoachingSourceKind: Hashable {
    case frontProject
    case logbook(UUID)
}

/// Which of the two the window shows, the pattern `ActiveEditor` set: Project ▸ Coaching… asks
/// for the front project, the Logbook's Coach… for a session.
@MainActor @Observable final class CoachingTarget {
    static let shared = CoachingTarget()

    private(set) var kind: CoachingSourceKind = .frontProject
    /// The session being read, kept while the window shows it so its file is read once.
    private(set) var logbookSource: LogbookCoachingSource?

    func showFrontProject() {
        kind = .frontProject
        logbookSource = nil
    }

    func show(_ entry: LogbookEntry) {
        if case .logbook(let id) = kind, id == entry.id, let logbookSource {
            logbookSource.entry = entry
            return
        }
        logbookSource = LogbookCoachingSource(entry: entry)
        kind = .logbook(entry.id)
    }
}

/// Where the lap being read comes from, and what the window may do with it. A project can seek,
/// film and plan; a logbook session is the numbers alone, and offers to make a project instead.
@MainActor protocol CoachingSource: AnyObject {
    /// Changes when the thing being read does, so the window reads it again.
    var id: String { get }
    /// The data input the lap comes from; a logbook session stands in with one made from its entry.
    var input: Input? { get }
    var session: TelemetrySession? { get }
    /// Why the session could not be read, when it could not.
    var problem: String? { get }
    var settings: CoachingSettings? { get }
    func setSettings(_ settings: CoachingSettings, undoName: String)
    /// The project behind the reading; `nil` for a logbook session, which has no playhead, no
    /// picture and no plan.
    var editor: EditorModel? { get }
    /// The logbook's key for the circuit the session is at, for the references offered.
    func circuitKey(for session: TelemetrySession) -> String
    /// The session's own bytes, so it is not offered as its own reference.
    var ownContentHash: String? { get }
    /// What the coaching sheet is headed with.
    var details: ProjectDetails { get }
    /// What the last export said, shown by a window with no status line of its own.
    var message: String? { get set }
    func load() async
    func exportSheet(_ sheet: CoachingSheet, as format: CoachingSheetFormat)
    /// The circuit a plan is kept for: its name, `nil` when the circuit is not known (#458).
    var planCircuitName: String? { get }
    /// What the circuit was left to try last time.
    var circuitPlan: NextSessionPlan? { get }
    /// Keeps `plan` for the circuit, and in the project — undoably — when there is one; `false`
    /// when there is nowhere to keep it (#458).
    func savePlan(_ plan: NextSessionPlan) -> Bool
    /// What Watch plays for `comparison`: this lap's corner, then the reference's when it has a
    /// picture; empty when nothing shows the corner (#516).
    func watchClips(
        for comparison: CornerComparison, analysis: CoachingAnalysis, selection: CoachingSelection
    ) async -> [WatchClip]
}

/// The front project, as the window has always read it.
@MainActor final class ProjectCoachingSource: CoachingSource {
    let editor: EditorModel?
    private let model: EditorModel

    init(editor: EditorModel) {
        self.editor = editor
        model = editor
    }

    var id: String { "project-\(ObjectIdentifier(model).hashValue)" }

    /// The input the settings name, else the one the laps come from.
    var input: Input? {
        if let id = model.project.coaching?.dataInputID,
            let input = model.project.dataInputs.first(where: { $0.id == id })
        {
            return input
        }
        return model.lapInput
    }

    var session: TelemetrySession? { input.flatMap { model.sessions[$0.id] } }
    var problem: String? { input.flatMap { model.problems[$0.id] } }
    var settings: CoachingSettings? { model.project.coaching }

    func setSettings(_ settings: CoachingSettings, undoName: String) {
        model.edit(undoName) { $0.coaching = settings }
    }

    func circuitKey(for session: TelemetrySession) -> String {
        guard let input else { return "" }
        return LogbookReferences.circuitKey(for: input, session: session, entries: LogbookModel.shared.entries)
    }

    var ownContentHash: String? {
        input?.dataSettings?.logbookEntryID.flatMap { id in
            LogbookModel.shared.entries.first { $0.id == id }?.file.contentHash
        }
    }

    var details: ProjectDetails { model.project.details }

    var message: String? {
        get { model.statusMessage }
        set { model.statusMessage = newValue }
    }

    func load() async {}

    func exportSheet(_ sheet: CoachingSheet, as format: CoachingSheetFormat) {
        model.exportCoachingSheet(sheet, as: format)
    }
}

/// One logbook session, read in on demand (#396): its choices are kept on the entry, a library
/// file, so they are not undoable — the Logbook's Undo is its own window's (#454), and the
/// Coaching window has none of its own for a session.
@MainActor @Observable final class LogbookCoachingSource: CoachingSource {
    var entry: LogbookEntry
    private(set) var session: TelemetrySession?
    private(set) var problem: String?
    var message: String?

    init(entry: LogbookEntry) {
        self.entry = entry
    }

    var id: String { "logbook-\(entry.id.uuidString)" }
    let editor: EditorModel? = nil

    /// A stand-in for the input a project would have: its id is the entry's, so settings saved
    /// on the entry name it.
    var input: Input? {
        var settings = DataInputSettings()
        settings.importerID = entry.file.importerID
        settings.logbookEntryID = entry.id
        return Input(
            id: InputID(entry.id), label: entry.title, source: MediaReference(path: entry.file.path),
            kind: .data(settings))
    }

    var settings: CoachingSettings? { entry.coaching }

    func setSettings(_ settings: CoachingSettings, undoName: String) {
        var changed = entry
        changed.coaching = settings
        entry = changed
        LogbookModel.shared.save(changed)
    }

    func circuitKey(for session: TelemetrySession) -> String { LogbookFilter.circuitKey(of: entry) }
    var ownContentHash: String? { entry.file.contentHash }

    /// The session as the sheet heads it: where, when, who, in what.
    var details: ProjectDetails {
        var details = ProjectDetails()
        details.track = entry.title
        details.date = entry.date.map { $0.formatted(date: .long, time: .omitted) } ?? ""
        details.driver = entry.driver
        details.car = entry.car
        return details
    }

    func load() async {
        guard session == nil else { return }
        if let loaded = await LogbookModel.shared.session(for: entry) {
            session = loaded
        } else {
            problem =
                "The session's file could not be read. It may have moved: Show in Finder in the Logbook says "
                + "where it was."
        }
    }

    func exportSheet(_ sheet: CoachingSheet, as format: CoachingSheetFormat) {
        switch CoachingSheetExporter.export(sheet, as: format) {
        case .success(let url): message = "Exported the coaching sheet as \(url.lastPathComponent)."
        case .failure(let error): message = "Could not write the coaching sheet: \(error.localizedDescription)"
        case nil: break
        }
    }
}
