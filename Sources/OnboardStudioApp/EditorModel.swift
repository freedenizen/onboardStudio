import AVFoundation
import AppKit
import Combine
import Foundation
import MediaKit
import Observation
import ProjectModel
import RenderKit
import SwiftUI
import TelemetryKit

/// Per-window editor state: selection, playback, the compiled preview, and the edit entry points
/// the views call. Owns a `PreviewController` that keeps an `AVPlayer` in sync with the project.
@Observable
final class EditorModel {
    let document: ProjectDocument
    var fileURL: URL?
    var undoManager: UndoManager?

    /// The object the inspector shows. Setting it — even to the object already there — means
    /// "just this one" and drops the rest of a multiple selection; `selectObject(_:extending:)`
    /// builds one. (Only on a change, a right-click Delete on the primary row deleted the whole
    /// selection.)
    var selectedObjectID: DisplayObjectID? {
        didSet { additionalSelection = [] }
    }
    /// The rest of a multiple selection, or of the selected object's group (#90).
    var additionalSelection: Set<DisplayObjectID> = []
    var selectedInputID: InputID?
    var selectedSegmentID: SegmentID?
    var selectedMarkerID: MarkerID?
    var showSyncWizard = false
    var showExport = false
    /// A lap or range to export as a phone clip; the sheet is open while this is set (#151).
    var clipRequest: ClipRequest?
    var showSaveTemplate = false
    /// Project ▸ Compare Laps… is open (#154).
    var showCompareLaps = false
    /// A scratch range marked with I and O (#230): shown on the ruler and offered by the export
    /// sheet. Not saved with the project, as a selection is not.
    var markIn: Double?
    var markOut: Double?
    /// The file to offer for upload, set when an export finishes or a file is chosen from the menu.
    var uploadURL: URL?
    var motionSyncTask: Task<Void, Never>?
    var motionSyncProgress: Double?
    /// Timeline magnification: 1 fits the whole project, larger values scroll.
    var timelineZoom: Double = 1
    /// Where the zoomed timeline is scrolled to, as a fraction of the whole (0 = start).
    var timelineScrollFraction: Double = 0
    /// Whether drags snap to clip edges and the playhead (the magnet).
    var snappingEnabled = true
    /// The first-run tour's current step, `nil` when it is not showing.
    var tourStep: Int?
    var errorMessage: String? {
        didSet { if let errorMessage { activity.record(errorMessage, isProblem: true) } }
    }
    /// What the app last did on the user's behalf, shown in the status line. Every message is also
    /// kept in `activity`, so one replacing another loses nothing (#112).
    var statusMessage: String? {
        didSet { if let statusMessage, statusMessage != oldValue { activity.record(statusMessage) } }
    }
    /// Everything the status line and the error alerts have said since the project opened.
    var activity = ActivityLog()
    /// The activity popover is open.
    var showActivity = false

    let preview = PreviewController()
    private(set) var loaded: ProjectCompiler.LoadedProject?
    /// Most recent import result, including ones superseded before they were applied, so the next
    /// compile can reuse whatever sessions and media info are still valid.
    private var reusableLoad: ProjectCompiler.LoadedProject?
    private var compileInFlight = false
    private var compilePending = false
    private var lastCompiledProject: Project?
    private var documentSubscription: AnyCancellable?

    /// Observed mirror of `document.project`. The document is an `ObservableObject`, which
    /// `@Observable` views do not track, so every document change (edits, undo, redo, revert)
    /// is copied here and triggers a recompile.
    private(set) var project: Project

    init(document: ProjectDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        project = document.project
        documentSubscription = document.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the mutation; read the new value on the next turn.
                DispatchQueue.main.async { self?.syncFromDocument() }
            }
    }

    func syncFromDocument() {
        guard document.project != project else { return }
        project = document.project
        // An undo can take away an object that is still selected; a selection naming objects
        // that no longer exist would group or delete nothing, or a group of one (#90).
        if let id = selectedObjectID, project.displayObject(id) == nil { selectedObjectID = nil }
        additionalSelection = additionalSelection.filter { project.displayObject($0) != nil }
        scheduleCompile()
    }
    var location: ProjectLocation {
        ProjectLocation(fileURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Untitled.onboardproj"))
    }
    var selectedObject: DisplayObject? { selectedObjectID.flatMap(project.displayObject) }
    var selectedSegment: Segment? { selectedSegmentID.flatMap(project.timeline.segment) }
    /// The segment in effect at the playhead: visibility, position and opacity edits go there.
    var editingSegment: Segment? { project.timeline.segment(at: currentTime) }
    /// Objects as they appear at the playhead.
    var resolvedObjects: [DisplayObject] { project.displayObjects(at: currentTime) }
    func resolvedObject(_ id: DisplayObjectID) -> DisplayObject? { resolvedObjects.first { $0.id == id } }
    var selectedInput: Input? { selectedInputID.flatMap(project.input) }
    var isPlaying: Bool { preview.isPlaying }
    var currentTime: Double { preview.currentTime }
    var duration: Double { preview.duration }
    var sessions: [InputID: TelemetrySession] { loaded?.sessions ?? [:] }
    /// Inputs whose files could not be loaded, with the reason.
    var problems: [InputID: String] { loaded?.problems ?? [:] }

    // MARK: - Editing

    func edit(_ name: String, _ change: (inout Project) -> Void) {
        document.apply(undoManager, name: name, change)
        syncFromDocument()
    }

    /// A data input added by the user that should be synced from timestamps once it has loaded.
    var pendingAutoSync: InputID?

    /// Called after every compile: applies a pending timestamp sync when the clocks allow it.
    func applyPendingAutoSync() {
        guard let id = pendingAutoSync, sessions[id] != nil else { return }
        pendingAutoSync = nil
        guard project.input(id)?.sync == SyncSettings() else { return }  // the user already changed it
        if let suggestion = suggestedSync(for: id) {
            updateInput(id, name: "Auto-Sync from Timestamps") { $0.sync = suggestion.sync }
            statusMessage =
                "Synced \(project.input(id)?.label ?? "data") from timestamps using the \(suggestion.videoClock)."
        }
    }

    // MARK: - Circuits

    /// A data input just added, whose circuit should be looked up once it has loaded.
    var pendingTrackLookup: InputID?

    /// A data input just added, whose file may name the track, driver and day (#74).
    var pendingDetails: InputID?

    /// The track definitions kept between projects.
    let trackLibrary = TrackLibrary()

    /// The data input whose start/finish line is being dragged about on the track map, if any.
    ///
    /// Editing is a mode rather than always-on because the map object is draggable itself: without
    /// it, reaching for the map would grab the line and reaching for the line would move the map.
    var startFinishEditing: InputID?

    /// The last map projection built for placing a line, kept so a redraw does not rebuild it.
    /// Not observed: it is a cache, and a view that read it would redraw for nothing.
    @ObservationIgnored var cachedProjection: (key: MapProjectionKey, projection: TrackProjection)?

    /// Called after every compile: names the circuit a freshly added file was recorded at and,
    /// if that circuit has a saved definition, applies its start/finish line and sectors.
    ///
    /// **Only for a file the user just added.** Opening a saved project must never do this, or a
    /// definition saved last week would silently change how a project renders today.
    func applyPendingTrackDefinition() {
        guard let id = pendingTrackLookup, let session = sessions[id] else { return }
        pendingTrackLookup = nil
        // The file's own gates outrank both a saved definition and anything derived from the
        // trace: the logger recorded where the line actually is, and no guess beats that (#71).
        if applyLapGeometry(of: session, to: id) { return }
        guard let match = CircuitCatalog.identify(session) else { return }
        guard let definition = trackLibrary.definition(id: match.circuit.id) else {
            updateInput(id, name: "Identify Circuit") {
                guard case .data(var settings) = $0.kind else { return }
                settings.circuitID = match.circuit.id
                $0.kind = .data(settings)
            }
            // A file that brought no laps of its own would otherwise open with nothing to time
            // against, leaving the driver to author a line from six decimal places. Only ever for
            // a file just added, and only when there is nothing to overrule.
            let recognised = "Recognised \(match.circuit.displayName)."
            if session.laps.isEmpty, suggestStartFinish(for: id) {
                statusMessage = recognised + " " + (statusMessage ?? "")
            } else {
                statusMessage = recognised
            }
            return
        }
        updateInput(id, name: "Apply Track Definition") {
            guard case .data(var settings) = $0.kind else { return }
            settings.circuitID = match.circuit.id
            if let line = definition.startFinish { settings.lapLine = line }
            settings.sectors = definition.sectors
            settings.cornerLabels = definition.cornerLabels
            $0.kind = .data(settings)
        }
        statusMessage = "Recognised \(definition.name) and used your saved start/finish and sectors."
    }

    /// The circuit a data input is at: what the project recorded, else what the file looks like.
    func circuit(for id: InputID) -> CircuitCatalog.Match? {
        guard let session = sessions[id] else { return nil }
        if case .data(let settings) = project.input(id)?.kind, let recorded = settings.circuitID,
            let circuit = CircuitCatalog.circuit(id: recorded)
        {
            return CircuitCatalog.match(circuit, to: session)
        }
        return CircuitCatalog.identify(session)
    }

    /// Saves this input's start/finish line and sectors against its circuit, for next time.
    func saveTrackDefinition(for id: InputID) {
        guard case .data(let settings) = project.input(id)?.kind, let match = circuit(for: id) else { return }
        let definition = TrackDefinition(
            circuitID: match.circuit.id, name: match.circuit.name, latitude: match.circuit.latitude,
            longitude: match.circuit.longitude, startFinish: settings.lapLine, sectors: settings.sectors,
            cornerLabels: settings.cornerLabels)
        do {
            try trackLibrary.save(definition)
            statusMessage = "Saved the start/finish and sectors for \(definition.name)."
        } catch {
            statusMessage = "Could not save the track: \(error.localizedDescription)"
        }
    }

    /// The corners this data input's reference lap has, for naming them.
    func corners(for id: InputID) -> [Corner] {
        guard let session = sessions[id], let reference = Sectors.referenceLap(in: session) else { return [] }
        return CornerDetector.corners(of: reference, in: session)
    }

    /// Names the `index`-th corner of `id`'s lap, padding the list out as needed so a label can
    /// be set on any corner without filling in the ones before it.
    func setCornerLabel(_ label: String, at index: Int, for id: InputID) {
        updateInput(id, name: "Name Corner") {
            guard case .data(var settings) = $0.kind, index >= 0 else { return }
            var labels = settings.cornerLabels
            while labels.count <= index { labels.append("") }
            labels[index] = label.trimmingCharacters(in: .whitespaces)
            // Trailing blanks carry no meaning and would grow the file for nothing.
            while let last = labels.last, last.isEmpty { labels.removeLast() }
            settings.cornerLabels = labels
            $0.kind = .data(settings)
        }
    }

    func forgetTrackDefinition(for id: InputID) {
        guard let match = circuit(for: id) else { return }
        try? trackLibrary.remove(id: match.circuit.id)
        statusMessage = "Forgot the saved settings for \(match.circuit.name)."
    }

    /// Adds an image input and an image object showing it.
    func addImage() {
        guard let url = OpenPanels.chooseImage() else { return }
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL),
            kind: .image(ImageInputSettings()))
        let object = DisplayObject.makeDefault(
            kind: .image(ImageObjectParams()), inputID: input.id, index: project.displayObjects.count)
        edit("Add Image") { project in
            project.inputs.append(input)
            project.displayObjects.append(object)
        }
        selectedObjectID = object.id
    }

    /// Adds an image input without an object (for gauge faces). Returns its id.
    @discardableResult
    func addImageInput() -> InputID? {
        guard let url = OpenPanels.chooseImage() else { return nil }
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL),
            kind: .image(ImageInputSettings()))
        edit("Add Image") { $0.inputs.append(input) }
        return input.id
    }

    // MARK: - Playback

    func togglePlayback() { preview.togglePlayback() }
    func seek(to time: Double) { preview.seek(to: time) }
    func step(by frames: Int) { preview.seek(to: currentTime + Double(frames) / project.settings.frameRate) }

    // MARK: - Compilation

    /// Rebuilds the preview after edits. Media/data are reloaded only when inputs change;
    /// object edits just swap the overlay plan.
    ///
    /// Compiles are serialised: a data import cannot be cancelled once it is running, so edits
    /// that arrive while one is in flight are coalesced into a single follow-up compile of the
    /// latest project, and a result for an outdated project is discarded.
    func scheduleCompile() {
        if compileInFlight {
            compilePending = true
            return
        }
        compileInFlight = true
        let project = self.project
        let location = self.location
        let previous = reusableLoad ?? loaded
        let needsRecompile = lastCompiledProject.map { ProjectCompiler.needsRecompile(from: $0, to: project) } ?? true
        Task { [weak self] in
            guard let self else { return }
            do {
                // Importing data and probing media is CPU-heavy; keep it off the main actor.
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try await ProjectCompiler.load(project, location: location, reusing: previous)
                }.value
                reusableLoad = loaded
                if project == self.project {
                    self.loaded = loaded
                    do {
                        if needsRecompile || preview.compiled == nil {
                            let compiled = try await ProjectCompiler.compile(loaded)
                            preview.replace(with: compiled)
                        } else if let current = preview.compiled {
                            preview.update(with: ProjectCompiler.replan(current, for: loaded))
                        }
                        lastCompiledProject = project
                        errorMessage = nil
                    } catch ProjectCompiler.LoadError.noPlayableVideo where project.videoInputs.isEmpty {
                        // Data with no video yet has nothing to play, but its sessions are loaded
                        // and a file just added still wants its circuit and details looked up.
                        errorMessage = nil
                    }
                    applyPendingAutoSync()
                    applyPendingTrackDefinition()
                    applyPendingDetails()
                    bindEmptyChannels()
                } else {
                    compilePending = true  // superseded by a newer edit
                }
            } catch {
                // An empty project has nothing to compile yet; that is not a problem to report.
                if case ProjectCompiler.LoadError.noPlayableVideo = error, project.videoInputs.isEmpty {
                    errorMessage = nil
                } else {
                    errorMessage = "\(error)"
                }
            }
            compileInFlight = false
            if compilePending {
                compilePending = false
                scheduleCompile()
            }
        }
    }
}

// Kept out of the class body, which SwiftLint holds to 250 lines.
extension EditorModel {
    func addVideo() {
        let urls = OpenPanels.chooseVideos(
            title: "Add Video", message: "Chapters of one recording are joined into one video.")
        guard !urls.isEmpty else { return }
        addVideos(at: urls)
    }

    func addData() {
        guard let url = OpenPanels.chooseData() else { return }
        addData(at: url)
    }
}
