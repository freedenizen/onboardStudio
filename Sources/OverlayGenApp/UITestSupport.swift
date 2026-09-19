import AppKit
import ProjectModel
import SwiftUI

/// Hooks for the XCUITest suite (`UITests/`). Active only when the app is launched with
/// `-uiTesting YES`; they replace the file panels the tests cannot drive with menu items that add
/// the fixture files, and let the export sheet write to a directory without a save panel.
enum UITestSupport {
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "uiTesting") }

    /// `OVERLAYGEN_FIXTURES`: the `Tests/Fixtures` directory.
    static var fixtures: URL? {
        ProcessInfo.processInfo.environment["OVERLAYGEN_FIXTURES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// `OVERLAYGEN_TEST_EXPORT_DIR`: where the export sheet writes instead of asking.
    static var exportDirectory: URL? {
        ProcessInfo.processInfo.environment["OVERLAYGEN_TEST_EXPORT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    static func fixture(_ name: String) -> URL? { fixtures?.appending(path: name) }

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
            path: "overlaygen-uitests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        let project = scratch.appending(path: "slice.overlayproj", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: project.path) { return project }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            for name in ["slice.overlayproj", "test-3s.mp4", "racerender-basic.csv"] {
                try FileManager.default.copyItem(at: fixtures.appending(path: name), to: scratch.appending(path: name))
            }
            return project
        } catch {
            return nil
        }
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
            Button("Add Fixture Data (GPX)") { add(data: "track.gpx") }
            Button("Add Fixture Image") {
                if let url = UITestSupport.fixture("arrow.png") { editor?.addImage(at: url) }
            }
            Divider()
            Button("Open Fixture Project") {
                guard let url = UITestSupport.scratchProject() else { return }
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
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
