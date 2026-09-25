import AppKit
import ProjectModel
import SwiftUI

/// Frame (#274): which part of the shot the finished video shows, the same for every video so
/// chapters and cameras stay framed alike (project inspector). A video's own crop is Crop, in the
/// video inspector.
struct CameraFramingSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        let framing = editor.project.settings.framing
        Section("Frame (all videos)") {
            Button("Frame on Preview") { editor.beginFraming() }
                .disabled(!editor.canFramePicture)
                .help("Drag the frame over the whole shot on the preview (⇧T)")
                .accessibilityIdentifier("frame.onPreview")
            SliderField(
                "Zoom", value: binding(\.zoom, "Zoom Frame"), in: 1...4, step: 0.05,
                scale: .plain(fractionDigits: 2), unit: "×", identifier: "frame.zoom")
            SliderField(
                "Horizontal", value: offset(\.centerX), in: -100...100, step: 1, unit: "%",
                identifier: "frame.horizontal"
            )
            .disabled(framing.zoom <= 1)
            .help("Move the framed window left or right; there is room to move it once zoomed in")
            SliderField(
                "Vertical", value: offset(\.centerY), in: -100...100, step: 1, unit: "%", identifier: "frame.vertical"
            )
            .disabled(framing.zoom <= 1)
            .help("Move the framed window up or down; there is room to move it once zoomed in")
            Text(
                "Zoom in, then move the window: its position is an offset from the centre, as a percentage of the "
                    + "frame. On the preview, drag the zoomed picture to move it."
            )
            .font(.caption).foregroundStyle(.secondary)
            // An edge trim shared by every video, from before this was Frame; kept, since projects
            // use it, but below the zoom that is usually what is wanted.
            SliderField(
                "Trim top", value: binding(\.crop.top, "Trim Frame"), in: 0...0.45, scale: .percent, unit: "%")
            SliderField(
                "Trim bottom", value: binding(\.crop.bottom, "Trim Frame"), in: 0...0.45, scale: .percent, unit: "%")
            SliderField(
                "Trim left", value: binding(\.crop.left, "Trim Frame"), in: 0...0.45, scale: .percent, unit: "%")
            SliderField(
                "Trim right", value: binding(\.crop.right, "Trim Frame"), in: 0...0.45, scale: .percent, unit: "%")
            Button("Reset Frame") { editor.setFraming({ $0 = .none }, name: "Reset Frame") }
                .disabled(framing.isIdentity)
                .help("Show the whole shot again, for every video")
            Text("Trimming cuts the same amount from every video's edges before zooming, on top of its own crop.")
                .font(.caption).foregroundStyle(.secondary)
        }
        // While the frame is being dragged on the preview these show it, and wait: a change here
        // would be an undo step inside a session that is meant to be one.
        .disabled(editor.pictureTool != nil)
    }

    /// Centre 0…1 shown as −100…100 (0 = centred), like an editor's position control.
    func offset(_ keyPath: WritableKeyPath<CameraFraming, Double>) -> Binding<Double> {
        Binding(
            get: { (editor.project.settings.framing[keyPath: keyPath] - 0.5) * 200 },
            set: { value in
                editor.setFraming({ $0[keyPath: keyPath] = min(max(value / 200 + 0.5, 0), 1) }, name: "Move Frame")
            })
    }

    func binding<T>(_ keyPath: WritableKeyPath<CameraFraming, T>, _ name: String) -> Binding<T> {
        Binding(
            get: { editor.project.settings.framing[keyPath: keyPath] },
            set: { value in editor.setFraming({ $0[keyPath: keyPath] = value }, name: name) })
    }
}

/// The guided checklist shown while a project is being put together.
struct GettingStartedSection: View {
    @Bindable var editor: EditorModel
    @AppStorage(Preferences.showGettingStarted.key) private var show = true

    var body: some View {
        if show {
            Section {
                ForEach(editor.gettingStartedSteps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.done ? Color.green : Color.secondary)
                            .padding(.top, 2)
                            .accessibilityLabel(step.done ? "Done" : "To Do")
                            .help(step.done ? "Done" : "Still to do")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).fontWeight(step.done ? .regular : .semibold)
                                .foregroundStyle(step.done ? .secondary : .primary)
                            if !step.done {
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                                Button(label(for: step.action)) { perform(step.action) }
                                    .controlSize(.small).padding(.top, 2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                HStack {
                    Button("Open the User Guide") { HelpLinks.open(.userGuide) }.controlSize(.small)
                    Spacer()
                    Button("Hide") { show = false }.controlSize(.small)
                }
            } header: {
                Text("Getting Started")
            }
        }
    }

    func label(for action: GettingStartedStep.Action) -> String {
        switch action {
        case .addVideo: "Add Video…"
        case .addData: "Add Data File…"
        case .useEmbedded: "Use the GoPro's GPS"
        case .sync: "Synchronize…"
        case .applyTemplate: "Apply the Classic Dash template"
        case .export: "Export Video…"
        }
    }

    func perform(_ action: GettingStartedStep.Action) {
        switch action {
        case .addVideo: editor.addVideo()
        case .addData: editor.addData()
        case .useEmbedded: if let video = editor.project.videoInputs.first { editor.useEmbeddedTelemetry(of: video.id) }
        case .sync:
            if let data = editor.project.dataInputs.first, editor.suggestedSync(for: data.id) != nil {
                editor.autoSync(data.id)
            } else {
                editor.showSyncWizard = true
            }
        case .applyTemplate: if let template = ProjectTemplate.builtIn.first { editor.apply(template) }
        case .export: if editor.canExport { editor.showExport = true }
        }
    }
}

/// What an empty project shows in place of the preview.
struct WelcomeOverlay: View {
    let editor: EditorModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 56)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Turn a lap video and its data into an overlay video").font(.title2)
                .accessibilityIdentifier("welcome.title")
            Text(
                "Add the video, add the data log (or use the GoPro's own GPS), then place gauges and export."
            )
            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 12) {
                Button {
                    editor.addVideo()
                } label: {
                    Label("Add Video…", systemImage: "video.badge.plus")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("welcome.addVideo")
                Button {
                    SampleProject.open()
                } label: {
                    Label("Open the Sample Project", systemImage: "play.rectangle")
                }
                .controlSize(.large).disabled(!SampleProject.isAvailable)
            }
            HStack(spacing: 16) {
                Button("User Guide") { HelpLinks.open(.userGuide) }
                Button("Supported Data Formats") { HelpLinks.open(.formats) }
            }
            .buttonStyle(.link).font(.callout)
        }
        .padding(32)
    }
}

/// Documentation links (the docs live in the repository; the app opens them in the browser).
enum HelpLinks {
    enum Page: String {
        case userGuide = "user-guide.md"
        case formats = "formats.md"
        case scripting = "scripting.md"
        case youtube = "youtube.md"
        case projectFormat = "project-format.md"
        case parity = "parity.md"
    }

    static let base = "https://github.com/freedenizen/onboardStudio/blob/main/docs/"

    /// Opens `page` in the browser, at `section` (a heading's anchor, such as `with-gyroflow`) if given.
    static func open(_ page: Page, section: String? = nil) {
        if let url = URL(string: base + page.rawValue + (section.map { "#" + $0 } ?? "")) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The bundled sample project (a short clip with a synthetic data log), copied to Documents so
/// it can be edited and saved.
enum SampleProject {
    static var bundled: URL? { Bundle.main.url(forResource: "Sample", withExtension: "onboardproj") }
    static var isAvailable: Bool { bundled != nil }

    static func open() {
        guard let source = bundled else { return }
        let documents =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destination = documents.appending(path: "Onboard Studio Sample.onboardproj")
        do {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            NSDocumentController.shared.openDocument(withContentsOf: destination, display: true) { _, _, error in
                if let error { NSAlert(error: error).runModal() }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// The keyboard shortcuts sheet (Help ▸ Keyboard Shortcuts).
struct ShortcutsView: View {
    static let rows: [(String, String)] = [
        ("⌘N / ⌘O / ⌘S", "New, open, save project"), ("⌘I", "Add video"), ("⇧⌘I", "Add camera (new lane)"),
        ("⇧⌘D", "Add data file"),
        ("⌘Y", "Synchronize data"), ("⌥⌘A", "Map attributes, for the selected data file"),
        ("⌘1 / ⌘2 / ⌘F", "In the attribute window: attributes, import report, filter"),
        ("⌘E", "Export video"), ("⌘K", "Add timeline segment at playhead"),
        ("M / ⌘M", "Add a marker at the playhead; ⌘M names it too"),
        ("⇧↑ / ⇧↓", "Previous / next marker"), ("⌥↑ / ⌥↓", "Previous / next lap"),
        ("⌘\\", "Split the selected video at the playhead"),
        ("⇧[ / ⇧]", "Trim the selected video's start / end to the playhead"),
        ("Space", "Play / pause"), (", .", "Step one frame"), ("Home", "Go to start"),
        ("Arrows (object selected)", "Nudge the object 1 px; ⇧ for 10 px"),
        ("← → (nothing selected)", "Step one frame"),
        ("↑ ↓ (in a number field)", "Add or subtract one"),
        ("⌘↩ (in a script)", "Apply the script"),
        ("⇧ while resizing", "Keep the object's aspect ratio"), ("⌘Z / ⇧⌘Z", "Undo / redo"),
        ("⇧⌘A", "Deselect all: the inspector shows the project"),
        ("⇧C / ⇧T", "Crop / frame the picture on the preview"),
        ("⌥⌘I", "Show / hide the inspector"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts").font(.title2)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                ForEach(Self.rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).font(.system(.body, design: .monospaced))
                        Text(row.1)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
