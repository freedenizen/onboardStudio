import Foundation
import MediaKit
import ProjectModel
import TelemetryKit

// MARK: - Projects and the logbook (#349)

extension EditorModel {
    /// Called after every compile: a data file the user has just added is entered in the logbook
    /// (when the preference says so), the input remembers its entry, and blank details are filled
    /// from the entry's car and driver. **Only for a file just added**, as the track definition
    /// and the details are; opening a saved project changes nothing.
    func enterPendingInLogbook() {
        guard let id = pendingLogbook, let session = sessions[id] else { return }
        pendingLogbook = nil
        guard UserDefaults.standard.value(for: Preferences.logbookAutoAdd), let input = project.input(id),
            let settings = input.dataSettings
        else { return }
        let url = dataFileURL(of: input)
        let logbook = AppLogbook.shared
        do {
            let request = ProjectLogbook.Request(
                url: url, session: session, importerID: settings.importerID, circuitID: circuit(for: id)?.circuit.id,
                car: project.details.car, driver: project.details.driver, runLines: RunLines(settings))
            let enrolment = try ProjectLogbook.enter(request, into: logbook)
            // Bookkeeping, not an edit the user made: no undo step of its own.
            document.apply(nil, name: "Enter in Logbook") { project in
                guard let index = project.inputs.firstIndex(where: { $0.id == id }),
                    case .data(var data) = project.inputs[index].kind
                else { return }
                data.logbookEntryID = enrolment.entry.id
                project.inputs[index].kind = .data(data)
            }
            syncFromDocument()
            fillDetails(fromEntry: enrolment.entry)
            LogbookModel.shared.reload()
            if enrolment.isNew { statusMessage = "Entered \(enrolment.entry.title) in the logbook." }
        } catch {
            statusMessage = "Could not enter the data file in the logbook: \(error.localizedDescription)"
        }
        recordProjectInLogbook()
    }

    /// Called after every compile: a data file the driver has since timed in runs, or moved the
    /// lines of, or put back to laps, is read the same way in the logbook (#552), so its entry lists
    /// the runs the project shows and is on the course they were driven on. Nothing happens while
    /// the two agree, which is every time a saved project is opened.
    func syncRunsToLogbook() {
        let logbook = AppLogbook.shared
        var changed = false
        for input in project.dataInputs {
            guard let settings = input.dataSettings, let id = settings.logbookEntryID, let session = sessions[input.id],
                var entry = logbook.entry(id: id)
            else { continue }
            let lines = RunLines(settings)
            guard entry.runLines != lines else { continue }
            entry.readRuns(lines, of: session, among: logbook.entries())
            try? logbook.save(entry)
            changed = true
        }
        if changed { LogbookModel.shared.reload() }
    }

    /// The car and the driver the logbook already knows, into blank details.
    func fillDetails(fromEntry entry: LogbookEntry) {
        var suggested = ProjectDetails()
        suggested.car = entry.car
        suggested.driver = entry.driver
        let (details, filled) = project.details.fillingBlanks(from: suggested)
        guard !filled.isEmpty else { return }
        edit("Fill In Project Details") { $0.details = details }
    }

    /// Where a data input's file is: the compiler's answer when it has one, else the reference
    /// resolved against the project's folder.
    func dataFileURL(of input: Input) -> URL {
        loaded?.mediaURLs[input.id] ?? input.source.resolved(relativeTo: location.baseDirectory)
    }

    /// Whether Coaching, opened on this project, would read the logbook session `entry` (#462):
    /// the data file it reads is that session's. A project that only has the session among other
    /// data files, and reads another, is not the session's project.
    func coaches(_ entry: LogbookEntry) -> Bool {
        guard let input = ProjectCoachingSource(editor: self).input else { return false }
        return entry.isSession(of: input, at: dataFileURL(of: input))
    }

    /// Every entry this project's data inputs came from.
    var logbookEntryIDs: [UUID] { project.dataInputs.compactMap { $0.dataSettings?.logbookEntryID } }

    /// The saved project on each of its entries, once it has a place on disk.
    func recordProjectInLogbook() {
        guard let fileURL, !logbookEntryIDs.isEmpty else { return }
        ProjectLogbook.record(project: fileURL, in: logbookEntryIDs, logbook: AppLogbook.shared)
    }

    /// An export on each entry, when it finishes.
    func recordExportInLogbook(_ url: URL) {
        guard !logbookEntryIDs.isEmpty else { return }
        ProjectLogbook.record(export: url, in: logbookEntryIDs, logbook: AppLogbook.shared)
        LogbookModel.shared.reload()
    }

    /// A data file that moved: the project's path no longer resolves but the entry's bookmark
    /// does, so the input takes the new place (undoable, and it compiles again); or the entry's
    /// path is stale while the project's is good, so the entry learns it. Once per load.
    func relinkThroughLogbook() {
        guard !relinkedThroughLogbook, loaded != nil else { return }
        relinkedThroughLogbook = true
        let logbook = AppLogbook.shared
        for input in project.dataInputs {
            guard let entryID = input.dataSettings?.logbookEntryID else { continue }
            if problems[input.id] != nil, let url = ProjectLogbook.relinkedURL(for: entryID, logbook: logbook),
                url != dataFileURL(of: input)
            {
                let base = fileURL
                updateInput(input.id, name: "Relink Data File") {
                    $0.source = MediaReference.make(for: url, relativeTo: base)
                }
                statusMessage = "Found \(url.lastPathComponent) where the logbook last saw it."
            } else if problems[input.id] == nil {
                ProjectLogbook.relink(entryID: entryID, to: dataFileURL(of: input), logbook: logbook)
            }
        }
    }
}
