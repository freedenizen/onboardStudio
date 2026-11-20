import ProjectModel
import SwiftUI
import TelemetryKit

/// Coaching's Data view (#556): the Analysis view on the coaching's session, its reference lap and
/// the lap being coached laid over each other to begin with.
struct CoachingDataTab: View {
    let source: any CoachingSource
    /// The reference lap first, then the coached lap.
    let laps: [Int]
    @State private var model = LapAnalysisModel()

    var body: some View {
        LapAnalysisView(model: model)
            .onAppear(perform: follow)
            .onChange(of: laps) { model.choose(laps) }
    }

    private func follow() {
        if let logbook = source as? LogbookCoachingSource {
            model.show(entry: logbook.entry, laps: laps)
        } else {
            model.showFrontProject(editor: source.editor, laps: laps)
        }
    }
}

extension CoachingContent {
    /// The laps Coaching compares, as the Analysis view takes them: its reference lap of the same
    /// session when it has one (else the session's best), then the coached lap.
    static func analysisLaps(_ selection: CoachingSelection, session: TelemetrySession) -> [Int] {
        let reference: Int? =
            switch selection.reference {
            case .lap(let number): number
            default: LapDeltas.sessionBest(in: session)?.number
            }
        return [reference, selection.lapNumber].compactMap { $0 }.reduce(into: []) { kept, number in
            if !kept.contains(number) { kept.append(number) }
        }
    }
}

/// The Logbook's Analysis view (#556): the selected session's laps, the logbook's others at its
/// circuit beside them.
struct LogbookAnalysisView: View {
    let entry: LogbookEntry?
    @State private var model = LapAnalysisModel()

    var body: some View {
        if let entry {
            LapAnalysisView(model: model)
                .onAppear { model.show(entry: entry) }
                .onChange(of: entry.id) { model.show(entry: entry) }
        } else {
            ContentUnavailableView(
                "Choose a Session", systemImage: "chart.xyaxis.line",
                description: Text(
                    "Select a session under Sessions, then come back to lay its laps over each other: delta-T, speed, "
                        + "any channel, the map and the friction circle."))
        }
    }
}
