import ProjectModel
import SwiftUI
import TelemetryKit

/// Two-step alignment: the current preview time is "the moment in the video"; the user scrubs the
/// data to the same moment using live readouts, and we solve for the data start position.
struct SyncWizardView: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var dataInputID: InputID?
    @State private var dataTime: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Synchronize Data with Video").font(.title2)
            Text(
                "1. Scrub the preview to a recognisable moment (braking, a gear change, crossing the line). "
                    + "That moment is at \(TimeParsing.lapTimeString(editor.currentTime)) in the project."
            )
            Picker("Data file", selection: $dataInputID) {
                ForEach(editor.project.dataInputs) { Text($0.label).tag(InputID?.some($0.id)) }
            }
            if let id = dataInputID, let session = editor.sessions[id], let range = session.timeRange {
                Text("2. Move the slider until the readouts match what you see in the video.")
                Slider(value: $dataTime, in: range)
                HStack {
                    Text("Data time: \(TimeParsing.lapTimeString(dataTime - range.lowerBound))").monospacedDigit()
                    Spacer()
                    Button("−1 s") { dataTime = max(range.lowerBound, dataTime - 1) }
                    Button("−0.1 s") { dataTime = max(range.lowerBound, dataTime - 0.1) }
                    Button("+0.1 s") { dataTime = min(range.upperBound, dataTime + 0.1) }
                    Button("+1 s") { dataTime = min(range.upperBound, dataTime + 1) }
                }
                readouts(session: session)
            } else {
                Text("Add a data file first.").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction).disabled(dataInputID == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            dataInputID =
                editor.selectedInput?.kind.isData == true ? editor.selectedInputID : editor.project.dataInputs.first?.id
            if let id = dataInputID, let input = editor.project.input(id) {
                dataTime = input.sync.inputTime(forProjectTime: editor.currentTime)
                if let range = editor.sessions[id]?.timeRange {
                    dataTime = min(max(dataTime, range.lowerBound), range.upperBound)
                }
            }
        }
    }

    @ViewBuilder func readouts(session: TelemetrySession) -> some View {
        let sample = TelemetrySampler(session: session).sample(at: dataTime)
        Grid(alignment: .leading, horizontalSpacing: 24) {
            GridRow {
                readout(
                    "Speed",
                    sample[.speed].map {
                        String(format: "%.0f mph", $0 * SpeedDisplayUnit.mph.factorFromMetersPerSecond)
                    })
                readout("RPM", sample[.rpm].map { String(format: "%.0f", $0) })
                readout("Gear", sample[.gear].map { String(format: "%.0f", $0) })
            }
            GridRow {
                readout("Lat G", sample[.lateralG].map { String(format: "%.2f", $0) })
                readout("Long G", sample[.longitudinalG].map { String(format: "%.2f", $0) })
                readout(
                    "Lap",
                    sample.lapTiming.currentLap.map {
                        "\($0.number)  \(TimeParsing.lapTimeString(sample.lapTiming.elapsedInLap ?? 0))"
                    })
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    func readout(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—")
        }
    }

    func apply() {
        guard let id = dataInputID, let input = editor.project.input(id) else { return }
        let start = SyncWizard.startPosition(projectTime: editor.currentTime, dataTime: dataTime, sync: input.sync)
        editor.updateInput(id, name: "Synchronize Data") { $0.sync.startPositionInInput = start }
        dismiss()
    }
}
