import AppKit
import ProjectModel
import SwiftUI

/// Zoom, pan and crop shared by every video (project inspector).
struct CameraFramingSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        let framing = editor.project.settings.framing
        Section("Transform (all videos)") {
            HStack {
                Slider(value: binding(\.zoom), in: 1...4, step: 0.05) { Text("Zoom") }
                NumberField("", value: binding(\.zoom), fractionDigits: 2...2).frame(width: 60)
            }
            HStack {
                Slider(value: offset(\.centerX), in: -100...100, step: 1) { Text("Position X") }
                    .disabled(framing.zoom <= 1)
                NumberField("", value: offset(\.centerX), fractionDigits: 0...0).frame(width: 60)
            }
            HStack {
                Slider(value: offset(\.centerY), in: -100...100, step: 1) { Text("Position Y") }
                    .disabled(framing.zoom <= 1)
                NumberField("", value: offset(\.centerY), fractionDigits: 0...0).frame(width: 60)
            }
            Text("Position is the offset of the zoomed window from the centre, as a percentage of the frame.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Cropping (all videos)") {
            PercentSlider("Crop top", value: binding(\.crop.top), range: 0...0.45)
            PercentSlider("Crop bottom", value: binding(\.crop.bottom), range: 0...0.45)
            PercentSlider("Crop left", value: binding(\.crop.left), range: 0...0.45)
            PercentSlider("Crop right", value: binding(\.crop.right), range: 0...0.45)
            Button("Reset framing") { editor.setFraming({ $0 = .none }, name: "Reset Camera Framing") }
                .disabled(framing.isIdentity)
            Text("Applies on top of each video's own crop, so chapters and cameras stay framed together.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Centre 0…1 shown as −100…100 (0 = centred), like an editor's position control.
    func offset(_ keyPath: WritableKeyPath<CameraFraming, Double>) -> Binding<Double> {
        Binding(
            get: { (editor.project.settings.framing[keyPath: keyPath] - 0.5) * 200 },
            set: { value in editor.setFraming { $0[keyPath: keyPath] = min(max(value / 200 + 0.5, 0), 1) } })
    }

    func binding<T>(_ keyPath: WritableKeyPath<CameraFraming, T>) -> Binding<T> {
        Binding(
            get: { editor.project.settings.framing[keyPath: keyPath] },
            set: { value in editor.setFraming { $0[keyPath: keyPath] = value } })
    }
}

/// The guided checklist shown while a project is being put together.
struct GettingStartedSection: View {
    @Bindable var editor: EditorModel
    @AppStorage("showGettingStarted") private var show = true

    var body: some View {
        if show {
            Section {
                ForEach(editor.gettingStartedSteps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.done ? Color.green : Color.secondary)
                            .padding(.top, 2)
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
        case .export: editor.showExport = true
        }
    }
}

/// What an empty project shows in place of the preview.
struct WelcomeOverlay: View {
    let editor: EditorModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 56)).foregroundStyle(.secondary)
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
                Button("Supported data formats") { HelpLinks.open(.formats) }
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

    static func open(_ page: Page) {
        if let url = URL(string: base + page.rawValue) { NSWorkspace.shared.open(url) }
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
        ("⌘Y", "Synchronize data (wizard)"), ("⌘E", "Export video"), ("⌘K", "Add timeline segment at playhead"),
        ("Space", "Play / pause"), ("← →", "Step one frame"), ("Home", "Go to start"),
        ("Arrow keys (object selected)", "Nudge the object; ⇧ for larger steps"),
        ("⇧ while resizing", "Keep the object's aspect ratio"), ("⌘Z / ⇧⌘Z", "Undo / redo"),
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
