import ProjectModel
import SwiftUI
import TelemetryKit

/// Laps or runs (#552): a circuit is timed from a line round to the same line, a point-to-point
/// course — an autocross, a hill climb, a stage — from a start line to a different finish line.
extension DataInputInspector {
    enum Timing: Hashable { case laps, runs }

    /// Laps or runs. Choosing runs sets both lines at once, at the preview position until they are
    /// moved, so the choice holds; choosing laps drops the finish and keeps the start as the line.
    @ViewBuilder var timingPicker: some View {
        Picker(
            "Timing",
            selection: Binding(
                get: { settings.timesRuns ? Timing.runs : .laps },
                set: { timing in
                    switch timing {
                    case .runs:
                        // The lines the driving suggests, else both at the preview to be moved.
                        if editor.suggestRunLines(for: input.id, name: "Time in Runs") { return }
                        update("Time in Runs") {
                            let here = currentPositionLine ?? LapLineSpec(latitude: 0, longitude: 0)
                            if $0.lapLine == nil { $0.lapLine = here }
                            $0.runFinishLine = here
                        }
                    case .laps:
                        update("Time in Laps") { $0.runFinishLine = nil }
                    }
                })
        ) {
            Text("Laps").tag(Timing.laps)
            Text("Runs").tag(Timing.runs)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("data.timing")
        .help("Laps for a circuit; runs from a start line to a finish line for an autocross, a hill climb or a stage")
    }

    /// The start and the finish of a point-to-point course.
    @ViewBuilder var runLines: some View {
        Text(
            "Each run is timed from the start line to the finish line. Runs are told apart by the car "
                + "stopping between them, so the course may pass either line on the way."
        )
        .font(.caption).foregroundStyle(.secondary)
        Button("Suggest Start and Finish from the Data") { editor.suggestRunLines(for: input.id) }
            .disabled(session == nil)
            .help("A start where runs set off from a standstill, and a finish where they ended")
            .accessibilityIdentifier("data.suggestRunLines")
        Button("Use Current Preview Position as Start") {
            setRunLine("Set Start") { $0.lapLine = $1 }
        }
        .disabled(!hasPosition)
        .accessibilityIdentifier("data.setRunStart")
        Toggle("Place the start on the track map", isOn: placingOnMap)
            .accessibilityIdentifier("data.placeStartFinish")
        lineFields(of: \.lapLine, name: "Start", undo: "Edit Start")
        Button("Use Current Preview Position as Finish") {
            setRunLine("Set Finish") { $0.runFinishLine = $1 }
        }
        .disabled(!hasPosition)
        .accessibilityIdentifier("data.setRunFinish")
        lineFields(of: \.runFinishLine, name: "Finish", undo: "Edit Finish")
    }

    /// Where a line is, which way it is crossed and how wide it is.
    @ViewBuilder func lineFields(
        of keyPath: WritableKeyPath<DataInputSettings, LapLineSpec?>, name: String, undo: String
    ) -> some View {
        if let line = settings[keyPath: keyPath] {
            NumberField(
                "\(name) latitude", value: lineBinding(keyPath, \.latitude, undo: undo), fractionDigits: 0...6,
                step: 0.0001)
            NumberField(
                "\(name) longitude", value: lineBinding(keyPath, \.longitude, undo: undo), fractionDigits: 0...6,
                step: 0.0001)
            NumberField(
                "\(name) heading (°)",
                value: Binding(
                    get: { line.headingDegrees ?? -1 },
                    set: { v in editLine(keyPath, undo: undo) { $0.headingDegrees = v < 0 ? nil : v } }))
            NumberField("\(name) half-width (m)", value: lineBinding(keyPath, \.halfWidthMeters, undo: undo))
        }
    }

    func lineBinding(
        _ line: WritableKeyPath<DataInputSettings, LapLineSpec?>, _ field: WritableKeyPath<LapLineSpec, Double>,
        undo: String
    ) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: line]?[keyPath: field] ?? 0 },
            set: { v in editLine(line, undo: undo) { $0[keyPath: field] = v } })
    }

    func editLine(
        _ keyPath: WritableKeyPath<DataInputSettings, LapLineSpec?>, undo: String,
        _ change: (inout LapLineSpec) -> Void
    ) {
        update(undo) { settings in
            guard var line = settings[keyPath: keyPath] else { return }
            change(&line)
            settings[keyPath: keyPath] = line
        }
    }

    /// Puts a line where the preview is, facing the way the car is going there.
    func setRunLine(_ undo: String, _ set: (inout DataInputSettings, LapLineSpec) -> Void) {
        guard let here = currentPositionLine else { return }
        update(undo) { set(&$0, here) }
    }

    /// Every lap or run with its time; a run that never reached the finish says DNF.
    @ViewBuilder var lapList: some View {
        if let session, !session.laps.listed.isEmpty {
            ForEach(session.laps.listed, id: \.number) { lap in
                LabeledContent(lap.title) {
                    HStack(spacing: 4) {
                        Text(lap.duration.map(TimeParsing.lapTimeString) ?? "—").monospacedDigit()
                        if lap.kind == .run, !lap.isComplete { Text("DNF") }
                    }
                    .foregroundStyle(lap.isComplete ? .primary : .secondary)
                }
            }
        } else {
            Text(settings.timesRuns ? "No runs found." : "No laps found.").foregroundStyle(.secondary)
        }
    }
}
