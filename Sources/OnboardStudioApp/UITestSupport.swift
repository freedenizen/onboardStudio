import AppKit
import Importers
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// Hooks for the XCUITest suite (`UITests/`). Active only when the app is launched with
/// `-uiTesting YES`; they replace the file panels the tests cannot drive with menu items that add
/// the fixture files, and let the export sheet write to a directory without a save panel.
enum UITestSupport {
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "uiTesting") }

    /// Where the widths of panes are kept: the app's preferences. Under the UI tests a store of
    /// their own, emptied at launch, so a test that drags a divider neither starts from the width
    /// the developer left in the real app nor leaves its own there. `-keepPaneWidths YES` keeps
    /// what the launch before left, for the test that quits and opens the app again.
    static let paneDefaults: UserDefaults = {
        let suite = "com.freedenizen.onboardstudio.uitests.panes"
        guard isActive, let store = UserDefaults(suiteName: suite) else { return .standard }
        if !UserDefaults.standard.bool(forKey: "keepPaneWidths") { store.removePersistentDomain(forName: suite) }
        return store
    }()

    /// `ONBOARD_FIXTURES`: the `Tests/Fixtures` directory.
    static var fixtures: URL? {
        ProcessInfo.processInfo.environment["ONBOARD_FIXTURES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// `ONBOARD_TEST_EXPORT_DIR`: where the export sheet writes instead of asking.
    static var exportDirectory: URL? {
        ProcessInfo.processInfo.environment["ONBOARD_TEST_EXPORT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    /// `ONBOARD_TEST_TEMPLATES_DIR`: a scratch folder for the user's templates, so a test that
    /// saves one never writes into the real Application Support. `nil` outside the UI tests.
    static var templatesDirectory: URL? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment["ONBOARD_TEST_TEMPLATES_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    /// `ONBOARD_TEST_TRACKS_DIR`: a scratch track library, so a test that plans a session never
    /// writes a plan onto the real circuit, and none of the user's circuits change what a test
    /// sees (#458). `nil` outside the UI tests.
    static var tracksDirectory: URL? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment["ONBOARD_TEST_TRACKS_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    /// `ONBOARD_TEST_LOGBOOK_DIR`: a scratch logbook, so a test never writes a track day into
    /// the real one. `nil` outside the UI tests.
    static var logbookDirectory: URL? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment["ONBOARD_TEST_LOGBOOK_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    static func fixture(_ name: String) -> URL? { fixtures?.appending(path: name) }

    /// Getting Started, in a project and in the Logbook, as on a first launch for every test, and
    /// nothing of the Logbook's checklist remembered (#451, #452). A launch argument cannot do it: it
    /// overrides what the app writes, so Hide could not hide anything under test.
    static func resetGettingStarted() {
        guard isActive else { return }
        for key in [
            Preferences.showGettingStarted.key, Preferences.showLogbookGettingStarted.key,
            Preferences.logbookCoached.key, Preferences.logbookSawProgress.key,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The coaching fixture one row shorter under its own name, entered straight into the logbook
    /// as `car` — a second visit to the same place in another car (#354).
    @MainActor
    static func addSecondVisit(to editor: EditorModel?, car: String) {
        guard let fixture = fixture("coaching-laps.csv"), let text = try? String(contentsOf: fixture, encoding: .utf8)
        else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "second-visit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "coaching-laps.csv")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        try? lines.dropLast(2).joined(separator: "\n").write(to: copy, atomically: true, encoding: .utf8)
        let day = secondVisitDay()
        Task {
            _ = await TrackDayImport.run([copy], into: AppLogbook.shared, car: car, day: day)
            LogbookModel.shared.reload()
            editor?.statusMessage = "Entered the second visit in the \(car)."
        }
    }

    /// The day a second visit to the coaching fixture's circuit goes on (#455). The fixture's file
    /// names no circuit and its trace lies at none of the catalogue, so two of its sessions are
    /// two visits to one place only once somebody says where that is — which is what this does,
    /// as a driver would: a session of the fixture already in the logbook is named (or keeps the
    /// circuit its day gave it), and the new visit goes on a day at the same circuit — the first
    /// visit's own day when that is at the circuit, else a new one. A new day is dated as the
    /// fixture's file is, so the fixture added to a project afterwards, which has no date of its
    /// own, lands on it and takes its circuit.
    @MainActor
    static func secondVisitDay() -> TrackDay {
        let logbook = AppLogbook.shared
        let visits = logbook.entries().filter {
            URL(fileURLWithPath: $0.file.path).lastPathComponent == "coaching-laps.csv"
        }
        let known = visits.first { !LogbookFilter.circuitKey(of: $0).isEmpty }
        // The first visit is on a day at its circuit already: the second joins it there, as it
        // did when both were filed by their date alone.
        if let known, let day = known.trackDayID.flatMap({ logbook.day(id: $0) }),
            day.circuitKey == LogbookFilter.circuitKey(of: known)
        {
            return day
        }
        let name = known?.trackName ?? "Stadium"
        for var visit in visits where known?.circuitID == nil && LogbookFilter.circuitKey(of: visit).isEmpty {
            visit.trackName = name
            try? logbook.save(visit)
        }
        let date = fixture("coaching-laps.csv").flatMap(Logbook.fileDate(at:)) ?? Date()
        let day = TrackDay(
            date: date, circuitID: known?.circuitID, trackName: known?.circuitID == nil ? name : nil)
        try? logbook.saveDay(day)
        LogbookModel.shared.reload()
        return day
    }

    /// Enters the RaceChrono v2 fixture and then puts its entry back to what a build before #477
    /// wrote: the laps of the old reading, and the first lap measurement.
    @MainActor
    static func addSessionReadBeforeTheLapFix() {
        guard let fixture = fixture("racechrono-v2.csv") else { return }
        Task {
            let logbook = AppLogbook.shared
            _ = await TrackDayImport.run([fixture], into: logbook)
            if var entry = logbook.entries().first(where: { $0.file.path == fixture.path }),
                let session = try? FormatDetector.importSession(
                    at: fixture, options: SessionBuilder.Options(legacyFirstLap: true))
            {
                entry.readLaps(of: session)
                entry.lapMeasurement = 1
                try? logbook.save(entry)
            }
            LogbookModel.shared.reload()
        }
    }

    /// The editor that appeared last. Headless CI runners do not always give the document window
    /// key status, which leaves `@FocusedValue(\.editor)` empty; the Testing menu falls back to this.
    static weak var currentEditor: EditorModel?

    /// Called when an editor appears under the UI tests: remembers it, brings the app to the
    /// front and keeps its windows inside the screen so every control is hittable.
    static func editorAppeared(_ editor: EditorModel) {
        guard isActive else { return }
        currentEditor = editor
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard let screen = NSScreen.main else { return }
            let visible = screen.visibleFrame
            for window in NSApp.windows where window.isVisible && !(window is NSPanel) {
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
                frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
                if frame != window.frame { window.setFrame(frame, display: true) }
            }
            NSApp.windows.last { $0.isVisible && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }
    }

    /// A copy of the fixture project (with the media it references) in a scratch folder, so tests
    /// can save it without touching the checkout. Made once per app launch, reused afterwards.
    static func scratchProject() -> URL? {
        guard let fixtures else { return nil }
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "onboard-uitests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        let project = scratch.appending(path: "slice.onboardproj", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: project.path) { return project }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            for name in ["slice.onboardproj", "test-3s.mp4", "racerender-basic.csv"] {
                try FileManager.default.copyItem(at: fixtures.appending(path: name), to: scratch.appending(path: name))
            }
            return project
        } catch {
            return nil
        }
    }
}

extension UITestSupport {
    /// Saves the project in `editor`'s window as "Saved Track Day", in a folder of its own under
    /// the temporary folder, as Save As would.
    static func saveAsScratchFile(_ editor: EditorModel?) {
        guard let window = editor?.window, let document = NSDocumentController.shared.document(for: window),
            let type = document.fileType
        else { return }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "onboard-uitests-saved-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suffix = document.fileNameExtension(forType: type, saveOperation: .saveAsOperation) ?? "onboardproj"
        let name = "Saved Track Day." + suffix
        document.save(to: folder.appending(path: name), ofType: type, for: .saveAsOperation) { _ in }
    }
}

/// The Testing menu: every item does what the matching open panel would, with a fixture file.
struct UITestCommands: Commands {
    @FocusedValue(\.editor) private var focused
    private var editor: EditorModel? { focused ?? UITestSupport.currentEditor }

    var body: some Commands {
        CommandMenu("Testing") {
            Button("Add Fixture Video") { add(video: "test-3s.mp4") }
            Button("Add Fixture Video Again") { add(video: "test-3s.mp4") }
            Button("Add Second Fixture Video") { add(video: "test-rot180.mp4") }
            Button("Add Fixture Camera") { add(video: "stereo-1s.mp4", asCamera: true) }
            Divider()
            Button("Add Fixture Data (RaceRender)") { add(data: "racerender-basic.csv") }
            Button("Add Fixture Data (RaceChrono)") { add(data: "racechrono-v3.csv") }
            Button("Add Fixture Data (Noisy CAN)") { add(data: "racechrono-v3-noisy.csv") }
            Button("Add Fixture Data (GPX)") { add(data: "track.gpx") }
            Button("Add Fixture Data (Coaching Laps)") { add(data: "coaching-laps.csv") }
            Button("Add Fixture Data (Autocross)") { add(data: "autocross.vbo") }
            // A folder dragged onto the window, which no test can drag (#466).
            Button("Drop Fixture Folder") {
                if let folder = UITestSupport.fixtures { editor?.addDroppedFiles([folder]) }
            }
            Button("Add Fixture Track Day") {
                guard let folder = UITestSupport.fixtures else { return }
                // Through the project in front, else the Logbook window (#395: there may be none).
                if let editor {
                    editor.trackDayRequest = TrackDayRequest(urls: [folder])
                } else {
                    LogbookModel.shared.trackDayRequest = TrackDayRequest(urls: [folder])
                }
            }
            // Into the day chosen in the Logbook window's sidebar (#393).
            Button("Add Fixture Sessions to Selected Day") {
                guard let folder = UITestSupport.fixtures else { return }
                let model = LogbookModel.shared
                model.trackDayRequest = TrackDayRequest(urls: [folder], day: model.selectedDay)
            }
            // A second visit to the coaching fixture's "circuit": the same file name, one row
            // shorter, so it is another session at the same place (#352).
            Button("Set Project Car Miata") { editor?.setDetail("Change Car") { $0.car = "Miata" } }
            Button("Add Fixture Second Visit in a GR86") { UITestSupport.addSecondVisit(to: editor, car: "GR86") }
            // A RaceChrono session as a build before #477 entered it: its first lap called partial,
            // and no note of a later reading (#498).
            Button("Add Fixture Session Read Before the Lap Fix") { UITestSupport.addSessionReadBeforeTheLapFix() }
            Button("Add Fixture Second Visit") {
                guard let fixture = UITestSupport.fixture("coaching-laps.csv"),
                    let text = try? String(contentsOf: fixture, encoding: .utf8)
                else { return }
                let folder = FileManager.default.temporaryDirectory.appending(path: "second-visit-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = folder.appending(path: "coaching-laps.csv")
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                try? lines.dropLast(2).joined(separator: "\n").write(to: copy, atomically: true, encoding: .utf8)
                // Onto a day at the circuit the first visit is at (#455).
                let day = UITestSupport.secondVisitDay()
                if let editor {
                    editor.trackDayRequest = TrackDayRequest(urls: [copy], day: day)
                } else {
                    LogbookModel.shared.trackDayRequest = TrackDayRequest(urls: [copy], day: day)
                }
            }
            Button("Add Fixture Image") {
                if let url = UITestSupport.fixture("arrow.png") { editor?.addImage(at: url) }
            }
            // What Save does, to a file of the tests' own in place of the save panel: a saved
            // project is called by its file, whatever it was called before (#481).
            Button("Save Project as Scratch File") { UITestSupport.saveAsScratchFile(editor) }
            Divider()
            Button("Open Fixture Project") {
                guard let url = UITestSupport.scratchProject() else { return }
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
            // The documentation screenshots (`DocumentationScreenshots`): a real project, a chosen
            // moment and one window size, so a rerun frames every picture the same way.
            Button("Open Screenshot Project") {
                guard let path = ProcessInfo.processInfo.environment["ONBOARD_TEST_SCREENSHOT_PROJECT"] else { return }
                NSDocumentController.shared.openDocument(
                    withContentsOf: URL(fileURLWithPath: path), display: true
                ) { _, _, _ in }
            }
            // The project's own files as a track day (#408): a saved project never enters its
            // sessions on opening, and the Logbook's picture should show a day, not an empty state.
            Button("Enter Screenshot Project in Logbook") {
                guard let editor else { return }
                let urls = editor.project.inputs.map { editor.location.resolve($0.source) }
                LogbookModel.shared.trackDayRequest = TrackDayRequest(urls: urls)
            }
            Button("Seek to Screenshot Time") {
                guard let text = ProcessInfo.processInfo.environment["ONBOARD_TEST_SCREENSHOT_TIME"],
                    let seconds = Double(text)
                else { return }
                editor?.seek(to: seconds)
            }
            Button("Size Window for Screenshots") {
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let screen = window.screen else { return }
                let size = CGSize(width: 1440, height: 860)
                let visible = screen.visibleFrame
                window.setFrame(
                    CGRect(
                        x: visible.midX - size.width / 2, y: visible.maxY - size.height, width: size.width,
                        height: size.height),
                    display: true)
            }
        }
    }

    private func add(video name: String, asCamera: Bool = false) {
        guard let url = UITestSupport.fixture(name) else { return }
        editor?.addVideos(at: [url], asCamera: asCamera)
    }

    private func add(data name: String) {
        guard let url = UITestSupport.fixture(name) else { return }
        editor?.addData(at: url)
    }
}
