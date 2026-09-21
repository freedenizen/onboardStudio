import ProjectModel
import SwiftUI
import TelemetryKit

/// Manual alignment, as a bar under the preview rather than a sheet over it.
///
/// Manual sync is the fallback for when auto-sync cannot do the job, so it matters most in the
/// awkward cases — and those are exactly the ones that need looking at the picture while nudging.
/// A modal sheet covered the video and could not be scrubbed behind, which forced the whole
/// alignment to be judged in one shot. Here every nudge applies immediately, so the preview and
/// the overlays redraw and the loop is nudge, look, nudge again. Undo covers a wrong move.
struct SyncPanelView: View {
    @Bindable var editor: EditorModel
    @State private var dataInputID: InputID?
    @State private var videoInputID: InputID?

    private var dataInput: Input? { dataInputID.flatMap(editor.project.input) }
    private var videoInput: Input? { videoInputID.flatMap(editor.project.input) }

    /// One frame of the project's rate — the finest step, and the reason this panel exists.
    private var frame: Double { SyncWizard.frameStep(frameRate: editor.project.settings.frameRate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if editor.project.dataInputs.isEmpty {
                Text("Add a data file to synchronize.").font(.callout).foregroundStyle(.secondary)
            } else {
                readouts
                controls
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear(perform: choose)
        .onChange(of: editor.project.inputs.count) { _, _ in choose() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Synchronize").font(.headline)
            Picker("", selection: $dataInputID) {
                ForEach(editor.project.dataInputs) { Text($0.label).tag(InputID?.some($0.id)) }
            }
            .labelsHidden().frame(maxWidth: 160).accessibilityIdentifier("sync.dataInput")
            if editor.project.videoInputs.count > 1 {
                Text("against").foregroundStyle(.secondary)
                Picker("", selection: $videoInputID) {
                    ForEach(editor.project.videoInputs) { Text($0.label).tag(InputID?.some($0.id)) }
                }
                .labelsHidden().frame(maxWidth: 160).accessibilityIdentifier("sync.videoInput")
            }
            Spacer()
            Text("Scrub to a moment you can recognise, then nudge until the numbers match it.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button("Done") { editor.showSyncWizard = false }
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("sync.done")
        }
    }

    /// What the data says at the moment now on screen, so it can be read against the picture
    /// instead of against a second scrubber.
    @ViewBuilder private var readouts: some View {
        let sample = dataInput.flatMap { input -> TelemetrySample? in
            guard let session = editor.sessions[input.id] else { return nil }
            return TelemetrySampler(session: session).sample(
                at: input.sync.inputTime(forProjectTime: editor.currentTime))
        }
        HStack(spacing: 18) {
            readout(
                "Speed",
                sample?[.speed].map { String(format: "%.0f mph", $0 * SpeedDisplayUnit.mph.factorFromMetersPerSecond) })
            readout("RPM", sample?[.rpm].map { String(format: "%.0f", $0) })
            readout("Gear", sample?[.gear].map { String(format: "%.0f", $0) })
            readout("Lat G", sample?[.lateralG].map { String(format: "%.2f", $0) })
            readout("Long G", sample?[.longitudinalG].map { String(format: "%.2f", $0) })
            readout(
                "Lap",
                sample?.lapTiming.currentLap.map {
                    "\($0.number)  \(TimeParsing.lapTimeString(sample?.lapTiming.elapsedInLap ?? 0))"
                })
            Spacer(minLength: 0)
        }
        .font(.system(.callout, design: .monospaced))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            nudgeRow("Data", input: dataInput, identifier: "data")
            Divider().frame(height: 16)
            nudgeRow("Video", input: videoInput, identifier: "video")
            Spacer(minLength: 0)
            // Both offsets, because either row can be the one being nudged and a nudge with no
            // number attached to it is a guess.
            VStack(alignment: .trailing, spacing: 1) {
                if let data = dataInput { offsetReadout("data", data.sync) }
                if let video = videoInput { offsetReadout("video", video.sync) }
            }
        }
    }

    private func offsetReadout(_ identifier: String, _ sync: SyncSettings) -> some View {
        let dropped = sync.inputSecondsBeforeProjectStart
        return Text(
            dropped > 0
                ? "\(identifier) \(String(format: "%+.3f s", sync.offsetInProject))  "
                    + String(format: "(first %.3f s unused)", dropped)
                : "\(identifier) \(String(format: "%+.3f s", sync.offsetInProject))"
        )
        .font(.caption).monospacedDigit()
        // Said plainly rather than prevented: moving an input earlier than the project's start is
        // a reasonable thing to ask for, and the part before the start simply cannot be shown.
        .foregroundStyle(dropped > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        .accessibilityIdentifier("sync.panelOffset.\(identifier)")
    }

    /// Moving the video against the data is the same job seen from the other side, and is the
    /// right move when the data is trustworthy and the camera started late.
    private func nudgeRow(_ title: String, input: Input?, identifier: String) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            nudge("−1s", identifier, input, -1)
            nudge("−.1", identifier, input, -0.1)
            nudge("−1f", identifier, input, -frame)
            nudge("+1f", identifier, input, frame)
            nudge("+.1", identifier, input, 0.1)
            nudge("+1s", identifier, input, 1)
        }
    }

    private func nudge(_ label: String, _ identifier: String, _ input: Input?, _ seconds: Double) -> some View {
        Button(label) {
            guard let input else { return }
            editor.updateInput(input.id, name: "Synchronize \(input.label)") {
                $0.sync = SyncWizard.shifted($0.sync, byProjectSeconds: seconds)
            }
        }
        .font(.caption).monospacedDigit().disabled(input == nil)
        .accessibilityIdentifier("sync.\(identifier)\(label.replacingOccurrences(of: "−", with: "-"))")
    }

    private func readout(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value ?? "—")
        }
    }

    private func choose() {
        if dataInput == nil {
            dataInputID =
                editor.selectedInput?.kind.isData == true
                ? editor.selectedInputID : editor.project.dataInputs.first?.id
        }
        if videoInput == nil { videoInputID = editor.project.videoInputs.first?.id }
    }
}
