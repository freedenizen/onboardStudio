import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

extension EditorModel {
    /// Project ▸ Compare Laps… (#154).
    /// `range` narrows the export range (and where the playhead goes) to part of the lap — one
    /// corner, from the Coaching window (#322); by default it is the whole lap.
    func compareLaps(_ settings: LapComparisonSettings, range: ClosedRange<Double>? = nil) {
        let range = range ?? projectRange(ofLap: settings.lap.lap, in: settings.lap.dataInputID)
        edit("Compare Laps") { $0.compareLaps(settings, lapRange: range) }
        selectedObjectID = nil
        selectedSegmentID = nil
        if let range { seek(to: range.lowerBound) }
    }

    /// Project ▸ Stop Comparing Laps.
    func stopComparingLaps() {
        edit("Stop Comparing Laps") { $0.stopComparingLaps() }
        selectedObjectID = nil
    }

    /// The complete, timed laps of a data input, for choosing one to compare.
    func comparableLaps(in dataInputID: InputID) -> [Lap] {
        (sessions[dataInputID]?.laps ?? []).filter { $0.isComplete && $0.duration != nil }
    }

    /// Where `lap` of a data input plays, in project seconds.
    func projectRange(ofLap number: Int, in dataInputID: InputID) -> ClosedRange<Double>? {
        guard let input = project.input(dataInputID),
            let lap = sessions[dataInputID]?.laps.first(where: { $0.number == number }), let end = lap.end
        else { return nil }
        let start = input.sync.projectTime(forInputTime: lap.start)
        let finish = input.sync.projectTime(forInputTime: end)
        return finish > start ? start...finish : nil
    }

    /// The camera that filmed a data input: the video it shares a clock with — embedded telemetry
    /// and a sidecar log follow their video — else the video in the same place in the list.
    func camera(for dataInputID: InputID) -> InputID? {
        let videos = project.videoInputs
        guard let data = project.input(dataInputID), !videos.isEmpty else { return nil }
        if let shared = videos.first(where: { $0.sync == data.sync }) { return shared.id }
        let index = project.dataInputs.firstIndex { $0.id == dataInputID } ?? 0
        return videos[min(index, videos.count - 1)].id
    }
}

/// Project ▸ Compare Laps… (#154): which lap to play, which to compare it with, and how the two
/// pictures share the frame. The compared lap is kept level with the other by distance.
struct CompareLapsSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var lapData: InputID?
    @State private var lap: Int?
    @State private var lapVideo: InputID?
    @State private var comparedData: InputID?
    @State private var comparedLap: Int?
    @State private var comparedVideo: InputID?
    /// The compared side as a spliced lap (#328) rather than one of its laps.
    @State private var comparedSplice: LapComparisonSettings.ComparedSplice?
    @State private var layout = LapComparisonLayout.sideBySide

    /// What the compared side's lap picker offers: a lap, or a spliced lap of the same data.
    enum ComparedChoice: Hashable {
        case lap(Int)
        case splice(LapComparisonSettings.ComparedSplice)
    }

    var settings: LapComparisonSettings? {
        guard let lapData, let lap, let lapVideo, let comparedData, let comparedVideo else { return nil }
        // A spliced side needs a lap number only as a placeholder: the lap playing will do.
        guard let comparedLap = comparedLap ?? (comparedSplice != nil ? lap : nil) else { return nil }
        let first = LapComparisonSettings.Side(dataInputID: lapData, videoInputID: lapVideo, lap: lap)
        let second = LapComparisonSettings.Side(
            dataInputID: comparedData, videoInputID: comparedVideo, lap: comparedLap)
        if first == second, comparedSplice == nil { return nil }
        return LapComparisonSettings(lap: first, comparedLap: second, layout: layout, comparedSplice: comparedSplice)
    }

    var comparedChoice: Binding<ComparedChoice?> {
        Binding(
            get: {
                if let comparedSplice { return .splice(comparedSplice) }
                return comparedLap.map { .lap($0) }
            },
            set: { choice in
                switch choice {
                case .lap(let number):
                    comparedLap = number
                    comparedSplice = nil
                case .splice(let splice):
                    comparedSplice = splice
                case nil:
                    comparedLap = nil
                    comparedSplice = nil
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare Laps").font(.title2)
            Text(
                "The lap plays as usual; the compared lap plays beside it, slowed down or sped up so it is always "
                    + "at the same point round the track. The delta between them shows beneath."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Section("Lap") {
                    side(data: $lapData, lap: $lap, video: $lapVideo, identifier: "compare.lap")
                }
                Section("Compared with") {
                    side(
                        data: $comparedData, lap: $comparedLap, video: $comparedVideo,
                        identifier: "compare.comparedLap", choice: comparedChoice)
                }
                Picker("Layout", selection: $layout) {
                    ForEach(LapComparisonLayout.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            if settings == nil, lap != nil, comparedLap != nil, comparedSplice == nil {
                Label("Choose two different laps.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if comparedSplice != nil {
                Text(
                    "A spliced lap's picture is cut from the laps it came from, so it jumps at each join; its "
                        + "readouts show the lap it is in at that moment."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Text("Replaces the objects in this project with the comparison layout. Undo puts them back.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    guard let settings else { return }
                    editor.compareLaps(settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings == nil)
                .accessibilityIdentifier("compare.ok")
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: chooseDefaults)
    }

    /// A data input (when there is more than one), one of its laps, and its camera (likewise).
    /// `choice`, for the compared side, offers the spliced laps as well (#328).
    @ViewBuilder
    func side(
        data: Binding<InputID?>, lap: Binding<Int?>, video: Binding<InputID?>, identifier: String,
        choice: Binding<ComparedChoice?>? = nil
    ) -> some View {
        let dataInputs = editor.project.dataInputs
        if dataInputs.count > 1 {
            Picker("Data", selection: data) {
                ForEach(dataInputs) { Text($0.label).tag(Optional($0.id)) }
            }
            .onChange(of: data.wrappedValue) { _, id in
                guard let id else { return }
                lap.wrappedValue = editor.comparableLaps(in: id).first?.number
                video.wrappedValue = editor.camera(for: id)
            }
        }
        let laps = data.wrappedValue.map(editor.comparableLaps) ?? []
        if let choice {
            Picker("Lap", selection: choice) {
                ForEach(laps, id: \.number) { lap in
                    Text("Lap \(lap.number) — \(TimeParsing.lapTimeString(lap.duration ?? 0, decimals: 2))")
                        .monospacedDigit().tag(Optional(ComparedChoice.lap(lap.number)))
                }
                if laps.count > 1 {
                    Divider()
                    ForEach(LapComparisonSettings.ComparedSplice.allCases, id: \.self) { splice in
                        Text(splice.displayName).tag(Optional(ComparedChoice.splice(splice)))
                    }
                }
            }
            .accessibilityIdentifier(identifier)
        } else {
            Picker("Lap", selection: lap) {
                ForEach(laps, id: \.number) { lap in
                    Text("Lap \(lap.number) — \(TimeParsing.lapTimeString(lap.duration ?? 0, decimals: 2))")
                        .monospacedDigit().tag(Optional(lap.number))
                }
            }
            .accessibilityIdentifier(identifier)
        }
        if laps.isEmpty {
            Text("This data has no complete laps.").font(.caption).foregroundStyle(.secondary)
        }
        let videos = editor.project.videoInputs
        if videos.count > 1 {
            Picker("Camera", selection: video) {
                ForEach(videos) { Text($0.label).tag(Optional($0.id)) }
            }
        }
    }

    /// The lap at the playhead against the session's best, or the next lap when that is the best.
    func chooseDefaults() {
        if let current = editor.project.lapComparison {
            (lapData, lap, lapVideo) = (current.lap.dataInputID, current.lap.lap, current.lap.videoInputID)
            (comparedData, comparedLap, comparedVideo) = (
                current.comparedLap.dataInputID, current.comparedLap.lap, current.comparedLap.videoInputID
            )
            comparedSplice = current.comparedSplice
            layout = current.layout
            return
        }
        guard let data = editor.project.dataInputs.first else { return }
        let laps = editor.comparableLaps(in: data.id)
        let now = data.sync.inputTime(forProjectTime: editor.currentTime)
        let playing = laps.first { $0.start <= now && now < ($0.end ?? $0.start) } ?? laps.first
        let best = editor.sessions[data.id].flatMap(LapDeltas.sessionBest)
        let other = best.flatMap { best in laps.first { $0.number == best.number } }
        let compared = other?.number != playing?.number ? other : laps.first { $0.number != playing?.number }
        lapData = data.id
        comparedData = data.id
        lap = playing?.number
        comparedLap = compared?.number
        lapVideo = editor.camera(for: data.id)
        comparedVideo = lapVideo
    }
}

extension TimerInspector {
    /// What *Compare with* offers: *Compared lap* only while the project compares laps (#154).
    var references: [LapReference] {
        let comparing = editor.project.lapComparison != nil || params.deltaReference == .comparedLap
        return LapReference.allCases.filter { comparing || $0 != .comparedLap }
    }
}
