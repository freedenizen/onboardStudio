import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// Project ▸ Export Coaching Debrief… (#327): the session as one short video — a title card,
/// the corners that cost the most as clips in the project's own layout, and a closing card with
/// what to try next session. The project itself is not touched.
struct DebriefSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var cornerCount = 3
    @State private var plan: DebriefPlan?
    @State private var reading = true
    @State private var progress: ExportProgress?
    @State private var task: Task<Void, Never>?
    @State private var finishedURL: URL?
    @State private var failure: String?

    private var hasCallout: Bool {
        editor.project.displayObjects.contains {
            if case .cornerCallout = $0.kind { return true } else { return false }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Coaching Debrief").font(.title2)
            HStack(alignment: .top, spacing: 16) {
                TemplatePicture(template: ProjectTemplate.coachingDebrief, width: 160)
                    .frame(width: 160, height: 90)
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "One video: a title card with the session's numbers, the corners that cost the most "
                            + "against the coaching reference as clips in this project's layout, and a closing "
                            + "card with what to try next session."
                    )
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !hasCallout {
                        Text(
                            "Tip: Project ▸ Apply Template ▸ Coaching Debrief puts the Corner Callout and the "
                                + "following track map on the clips."
                        )
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Stepper(value: $cornerCount, in: 1...6) {
                Text("Corners: \(cornerCount)")
            }
            .accessibilityIdentifier("debrief.corners")
            segments
            if let progress {
                ProgressView(value: progress.fraction) {
                    Text(finishedURL == nil ? "Exporting…" : "Done: \(finishedURL?.lastPathComponent ?? "")")
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 520)
        .task(id: cornerCount) { await read() }
    }

    @ViewBuilder private var segments: some View {
        if reading {
            ProgressView().controlSize(.small)
        } else if let plan {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(plan.segmentTitles.enumerated()), id: \.offset) { _, title in
                    Text(title).monospacedDigit()
                }
                Text("\(TimeParsing.lapTimeString(plan.duration)) in all").foregroundStyle(.secondary)
                if plan.corners.isEmpty {
                    Text(
                        "No corner of the coaching lap lost time inside this project's video, "
                            + "so the debrief is the two cards."
                    )
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("debrief.segments")
        } else {
            Text("Coaching needs a data file with at least two complete laps and a GPS trace.")
                .foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            if task != nil {
                Button("Cancel") { task?.cancel() }
            } else {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if let finishedURL {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finishedURL]) }
                        .accessibilityIdentifier("debrief.reveal")
                    Button("Upload to YouTube…") {
                        dismiss()
                        editor.uploadURL = finishedURL
                    }
                }
                Button("Export…", action: start).keyboardShortcut(.defaultAction)
                    .disabled(plan == nil)
                    .accessibilityIdentifier("debrief.export")
            }
        }
    }

    /// The plan, read off the main thread: the coaching read is the expensive part.
    func read() async {
        reading = true
        guard let loaded = editor.loadedForExport else {
            plan = nil
            reading = false
            return
        }
        let duration = editor.duration
        let count = cornerCount
        let made = await Task.detached(priority: .userInitiated) {
            DebriefPlan.make(in: loaded, duration: duration, cornerCount: count)
        }.value
        guard !Task.isCancelled else { return }
        plan = made
        reading = false
    }

    func start() {
        guard let loaded = editor.loadedForExport, let plan else {
            failure = "The project has not finished loading."
            return
        }
        let base = editor.fileURL?.deletingPathExtension().lastPathComponent ?? "Onboard Studio Export"
        let settings = editor.project.export.reconciled
        guard
            let url = OpenPanels.chooseExportDestination(
                suggestedName: "\(base) – Coaching Debrief.\(settings.fileExtension)",
                fileExtension: settings.fileExtension)
        else { return }
        failure = nil
        finishedURL = nil
        progress = ExportProgress(fraction: 0, framesWritten: 0, currentTime: 0)
        task = Task {
            do {
                let compiled = ProjectCompiler.prepareForExport(
                    try await ProjectCompiler.compile(loaded), settings: settings)
                var throttle = ProgressThrottle()
                for try await update in DebriefExporter.export(
                    compiled, project: loaded.project, plan: plan, settings: settings, to: url)
                where throttle.shouldReport(update.fraction) {
                    progress = update
                }
                finishedURL = url
                editor.statusMessage = "Exported the coaching debrief."
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
