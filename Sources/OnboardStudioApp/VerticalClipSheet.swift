import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// One stretch of the project to export as a phone clip (#151).
struct ClipRequest: Identifiable {
    let id = UUID()
    /// "Lap 7" or a marker's name: what the clip is of, and what its file is called after.
    let title: String
    let start: Double
    let end: Double
}

extension EditorModel {
    /// Project ▸ Export Lap as Vertical Clip…: the lap at the playhead.
    func requestLapClip() {
        guard let loaded, let lap = ProjectCompiler.lap(at: currentTime, in: loaded, duration: duration) else {
            statusMessage = "Put the playhead in a lap to export it as a clip."
            return
        }
        clipRequest = ClipRequest(title: "Lap \(lap.lap)", start: lap.range.lowerBound, end: lap.range.upperBound)
    }

    /// A marker's range, or the lap a point marker falls in.
    func requestClip(of placed: PlacedMarker) {
        if placed.marker.isRange, placed.end > placed.start {
            let name = placed.marker.name.isEmpty ? "Range" : placed.marker.name
            clipRequest = ClipRequest(title: name, start: placed.start, end: placed.end)
        } else if let loaded, let lap = ProjectCompiler.lap(at: placed.start, in: loaded, duration: duration) {
            clipRequest = ClipRequest(title: "Lap \(lap.lap)", start: lap.range.lowerBound, end: lap.range.upperBound)
        } else {
            statusMessage = "That marker is not in a lap; a range marker exports its own range."
        }
    }
}

/// Exports one lap or range as a 9:16 clip laid out by the Social template, in one step: the
/// project itself is not touched (#151).
struct VerticalClipSheet: View {
    @Bindable var editor: EditorModel
    let request: ClipRequest
    @Environment(\.dismiss) private var dismiss
    @State private var progress: ExportProgress?
    @State private var task: Task<Void, Never>?
    @State private var finishedURL: URL?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export \(request.title) as a Vertical Clip").font(.title2)
            HStack(alignment: .top, spacing: 16) {
                TemplatePicture(template: ProjectTemplate.social, width: 90)
                    .frame(width: 90, height: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "\(TimeParsing.lapTimeString(request.start)) – \(TimeParsing.lapTimeString(request.end))"
                    )
                    .monospacedDigit()
                    .accessibilityIdentifier("clip.range")
                    Text(
                        "1080 × 1920, laid out by the Social template: the whole picture across the middle, "
                            + "the stat card above, lap timer, speed and map below. Your project stays as it is."
                    )
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let progress {
                ProgressView(value: progress.fraction) {
                    Text(finishedURL == nil ? "Exporting…" : "Done: \(finishedURL?.lastPathComponent ?? "")")
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Spacer()
                if task != nil {
                    Button("Cancel") { task?.cancel() }
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    if let finishedURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finishedURL]) }
                            .accessibilityIdentifier("clip.reveal")
                        Button("Upload to YouTube…") {
                            dismiss()
                            editor.uploadURL = finishedURL
                        }
                    }
                    Button("Export…", action: start).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("clip.export")
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    func start() {
        guard var loaded = editor.loadedForExport else {
            failure = "The project has not finished loading."
            return
        }
        let base = editor.fileURL?.deletingPathExtension().lastPathComponent ?? "Onboard Studio Export"
        let clip = editor.project.verticalClip(from: request.start, to: request.end)
        let settings = clip.export.reconciled
        guard
            let url = OpenPanels.chooseExportDestination(
                suggestedName: "\(base) – \(request.title) (vertical).\(settings.fileExtension)",
                fileExtension: settings.fileExtension)
        else { return }
        loaded.project = clip
        failure = nil
        finishedURL = nil
        progress = ExportProgress(fraction: 0, framesWritten: 0, currentTime: 0)
        let range = request.start...request.end
        task = Task {
            do {
                let compiled = ProjectCompiler.prepareForExport(
                    try await ProjectCompiler.compile(loaded), settings: settings)
                var throttle = ProgressThrottle()
                for try await update in Exporter.export(compiled, settings: settings, range: range, to: url)
                where throttle.shouldReport(update.fraction) {
                    progress = update
                }
                finishedURL = url
                editor.statusMessage = "Exported \(request.title) as a vertical clip."
            } catch is CancellationError {
                failure = "Export cancelled."
                progress = nil
            } catch {
                failure = "\(error)"
                progress = nil
            }
            task = nil
        }
    }
}
