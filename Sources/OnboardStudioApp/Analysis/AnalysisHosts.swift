import ProjectModel
import SwiftUI
import TelemetryKit

/// Coaching's Data view (#556): the Analysis view on the coaching's session, its reference lap and
/// the lap being coached laid over each other to begin with.
struct CoachingDataTab: View {
    let source: any CoachingSource
    /// The reference lap first, then the coached lap.
    let laps: [Int]
    /// Another session's lap as the reference, when that is what Coaching reads against (#669).
    var other: AnalysisOtherLap?
    @State private var model = LapAnalysisModel()

    var body: some View {
        LapAnalysisView(model: model)
            .onAppear(perform: follow)
            .onChange(of: laps) { model.choose(laps, other: other) }
            .onChange(of: other) { model.choose(laps, other: other) }
    }

    private func follow() {
        if let logbook = source as? LogbookCoachingSource {
            model.show(entry: logbook.entry, laps: laps, other: other)
        } else {
            model.showFrontProject(editor: source.editor, laps: laps, other: other)
        }
    }
}

extension CoachingContent {
    /// Coaching's Data tab on what it is reading: the reference and the coached lap ticked.
    func dataTab(_ selection: CoachingSelection, session: TelemetrySession) -> some View {
        CoachingDataTab(
            source: source, laps: Self.analysisLaps(selection, session: session),
            other: Self.analysisOther(selection))
    }

    /// The laps Coaching compares, as the Analysis view takes them: its reference lap of the same
    /// session when it has one (else the session's best), then the coached lap.
    static func analysisLaps(_ selection: CoachingSelection, session: TelemetrySession) -> [Int] {
        let reference: Int? =
            switch selection.reference {
            case .lap(let number): number
            // Another session's lap is the reference; it is not one of this session's (#669).
            case .logbook: nil
            default: LapDeltas.sessionBest(in: session)?.number
            }
        return [reference, selection.lapNumber].compactMap { $0 }.reduce(into: []) { kept, number in
            if !kept.contains(number) { kept.append(number) }
        }
    }

    /// The Logbook session Coaching reads against, for the Data view to tick as its reference.
    /// Compare With on the Data tab drew this session's best lap against the coached lap, and the
    /// session that was asked for was neither ticked nor on the charts (#669).
    static func analysisOther(_ selection: CoachingSelection) -> AnalysisOtherLap? {
        if case .logbook(let entryID, let lap) = selection.reference {
            AnalysisOtherLap(entry: entryID, lap: lap)
        } else {
            nil
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
