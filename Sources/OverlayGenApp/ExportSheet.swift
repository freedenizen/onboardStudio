import MediaKit
import ProjectModel
import SwiftUI

struct ExportSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var preset = "1080p"
    @State private var codec = ExportSettings.VideoCodec.h264
    @State private var bitrateMbps: Double = 16
    @State private var progress: ExportProgress?
    @State private var exportTask: Task<Void, Never>?
    @State private var finishedURL: URL?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Video").font(.title2)
            Form {
                Picker("Size", selection: $preset) {
                    let size = "\(editor.project.settings.outputWidth) × \(editor.project.settings.outputHeight)"
                    Text("Project size (\(size))").tag("project")
                    Text("1280 × 720").tag("720p")
                    Text("1920 × 1080").tag("1080p")
                    Text("3840 × 2160").tag("4k")
                }
                Picker("Codec", selection: $codec) {
                    Text("H.264").tag(ExportSettings.VideoCodec.h264)
                    Text("HEVC (H.265)").tag(ExportSettings.VideoCodec.hevc)
                }
                Slider(value: $bitrateMbps, in: 2...60, step: 1) { Text("Bitrate: \(Int(bitrateMbps)) Mbit/s") }
            }
            .formStyle(.columns)
            if let progress {
                ProgressView(value: progress.fraction) {
                    Text(
                        finishedURL == nil
                            ? "Exporting… \(progress.framesWritten) frames"
                            : "Done: \(finishedURL?.lastPathComponent ?? "")")
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Spacer()
                if exportTask != nil {
                    Button("Cancel") { exportTask?.cancel() }
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    if let finishedURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finishedURL]) }
                    }
                    Button("Export…") { start() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            preset = "project"
            codec = editor.project.export.codec
            bitrateMbps = Double(editor.project.export.videoBitrate) / 1_000_000
        }
    }

    func settings() -> ExportSettings {
        var settings = ExportSettings.presets[preset] ?? editor.project.export
        if preset == "project" {
            settings.width = editor.project.settings.outputWidth
            settings.height = editor.project.settings.outputHeight
        }
        settings.frameRate = editor.project.settings.frameRate
        settings.codec = codec
        settings.videoBitrate = Int(bitrateMbps * 1_000_000)
        return settings
    }

    func start() {
        let name = (editor.fileURL?.deletingPathExtension().lastPathComponent ?? "OverlayGen Export") + ".mp4"
        guard let destination = OpenPanels.chooseExportDestination(suggestedName: name) else { return }
        guard let loaded = editor.loaded else {
            failure = "The project has not finished loading."
            return
        }
        failure = nil
        finishedURL = nil
        progress = ExportProgress(fraction: 0, framesWritten: 0, currentTime: 0)
        let settings = settings()
        editor.edit("Change Export Settings") { $0.export = settings }
        exportTask = Task {
            do {
                let compiled = try await ProjectCompiler.compile(loaded)
                for try await update in Exporter.export(compiled, settings: settings, to: destination) {
                    progress = update
                }
                finishedURL = destination
            } catch is CancellationError {
                failure = "Export cancelled."
                progress = nil
            } catch {
                failure = "\(error)"
                progress = nil
            }
            exportTask = nil
        }
    }
}
