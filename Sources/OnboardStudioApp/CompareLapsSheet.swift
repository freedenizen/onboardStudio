import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

extension EditorModel {
    /// Project ▸ Compare Laps… (#154).
    func compareLaps(_ settings: LapComparisonSettings) {
        let range = projectRange(ofLap: settings.lap.lap, in: settings.lap.dataInputID)
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
    @State private var layout = LapComparisonLayout.sideBySide

    var settings: LapComparisonSettings? {
        guard let lapData, let lap, let lapVideo, let comparedData, let comparedLap, let comparedVideo else {
            return nil
        }
        let first = LapComparisonSettings.Side(dataInputID: lapData, videoInputID: lapVideo, lap: lap)
        let second = LapComparisonSettings.Side(
            dataInputID: comparedData, videoInputID: comparedVideo, lap: comparedLap)
        return first == second ? nil : LapComparisonSettings(lap: first, comparedLap: second, layout: layout)
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
                        data: $comparedData, lap: $comparedLap, video: $comparedVideo, identifier: "compare.comparedLap"
                    )
                }
                Picker("Layout", selection: $layout) {
                    ForEach(LapComparisonLayout.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            if settings == nil, lap != nil, comparedLap != nil {
                Label("Choose two different laps.", systemImage: "exclamationmark.triangle")
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
    @ViewBuilder
    func side(data: Binding<InputID?>, lap: Binding<Int?>, video: Binding<InputID?>, identifier: String)
        -> some View
    {
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
        Picker("Lap", selection: lap) {
            ForEach(laps, id: \.number) { lap in
                Text("Lap \(lap.number) — \(TimeParsing.lapTimeString(lap.duration ?? 0, decimals: 2))")
                    .monospacedDigit().tag(Optional(lap.number))
            }
        }
        .accessibilityIdentifier(identifier)
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
