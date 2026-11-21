import Foundation
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// The Analysis view's state (#556): the home session and the logbook's others at its circuit, the
/// laps chosen (the first is the reference), the analysis built from them, the place the cursor is
/// at, the span on screen, and the panels. One instance, as the window is one.
@MainActor @Observable final class LapAnalysisModel {
    static let shared = LapAnalysisModel()

    private(set) var kind: ReplaySourceKind = .frontProject
    var groups: [ReplaySessionGroup] = []
    /// Lap ids in order; the first is the reference.
    private(set) var chosen: [String] = []
    private(set) var problem: String?
    private(set) var isLoading = false
    private(set) var isBuilding = false
    private(set) var analysis: LapAnalysis?
    /// The picture of each trace that has one, by trace id (#556).
    private(set) var footage: [Int: AnalysisFootage] = [:]
    /// What the friction circle reads the laps against (#631).
    private(set) var gripTarget: GripTarget?
    let picture = AnalysisPicture()
    /// The project whose picture a project's laps are shown in.
    @ObservationIgnored private(set) weak var editor: EditorModel?
    /// Metres into the reference lap the cursor is at.
    var cursor: Double? {
        didSet { if cursor != oldValue { showPicture() } }
    }
    /// The span the traces show; `nil` is the whole lap.
    var visible: ClosedRange<Double>?
    var layout: AnalysisLayout {
        didSet {
            UserDefaults.standard.set(layout.preferenceText, for: Preferences.analysisLayout)
            if layout.channels != oldValue.channels { rebuild() }
        }
    }
    private var generation = 0
    /// The home session's laps to begin with, in order, when they are known: Coaching's reference
    /// and lap. Empty is the quickest two.
    private var preferredLaps: [Int] = []

    init() {
        layout = AnalysisLayout(preferenceText: UserDefaults.standard.value(for: Preferences.analysisLayout))
    }

    var hasSource: Bool { !groups.isEmpty || isLoading || problem != nil }
    var span: ClosedRange<Double> { visible ?? 0...(analysis?.length ?? 1) }

    // MARK: - Sources

    /// The front project's session with laps, its other data files beside it, and the logbook's
    /// other sessions at the circuit.
    func showFrontProject(editor: EditorModel?, laps: [Int] = []) {
        kind = .frontProject
        reset()
        self.editor = editor
        preferredLaps = laps
        guard let editor, let input = editor.lapInput, let session = editor.sessions[input.id] else {
            problem = editor == nil ? nil : "The project has no data file with laps."
            return
        }
        var groups = [
            ReplayModel.group(
                id: input.id.rawValue.uuidString, title: input.label, subtitle: "", session: session, isHome: true)
        ]
        for other in editor.project.dataInputs where other.id != input.id {
            guard let otherSession = editor.sessions[other.id] else { continue }
            groups.append(
                ReplayModel.group(
                    id: other.id.rawValue.uuidString, title: other.label, subtitle: "", session: otherSession,
                    isHome: false))
        }
        let key = LogbookReferences.circuitKey(for: input, session: session, entries: LogbookModel.shared.entries)
        let own = input.dataSettings?.logbookEntryID.flatMap { id in LogbookModel.shared.entries.first { $0.id == id } }
        groups += ReplayModel.logbookGroups(at: key, excluding: own?.file.contentHash)
        self.groups = groups
        chooseDefaults()
    }

    /// A logbook session, read in on demand, the logbook's other sessions at its circuit beside it.
    func show(entry: LogbookEntry, laps: [Int] = []) {
        if case .logbook(let id) = kind, id == entry.id, !groups.isEmpty {
            if !laps.isEmpty, laps != preferredLaps { choose(laps) }
            return
        }
        kind = .logbook(entry.id)
        reset()
        editor = nil
        preferredLaps = laps
        isLoading = true
        let key = LogbookFilter.circuitKey(of: entry)
        Task { @MainActor in
            guard let session = await LogbookModel.shared.session(for: entry) else {
                isLoading = false
                problem =
                    "The session's file could not be read. It may have moved: Show in Finder in the Logbook says "
                    + "where it was."
                return
            }
            guard case .logbook(let current) = kind, current == entry.id else { return }
            groups =
                [
                    ReplayModel.group(
                        id: entry.id.uuidString, title: entry.title, subtitle: ReplayModel.subtitle(of: entry),
                        session: session, entry: entry, isHome: true)
                ] + ReplayModel.logbookGroups(at: key, excluding: entry.file.contentHash)
            isLoading = false
            chooseDefaults()
        }
    }

    private func reset() {
        groups = []
        chosen = []
        problem = nil
        analysis = nil
        footage = [:]
        gripTarget = nil
        picture.stop()
        cursor = nil
        visible = nil
        generation += 1
    }

    /// The laps asked for, else the home session's best lap as the reference and its next quickest
    /// against it.
    private func chooseDefaults() {
        guard let home = groups.first(where: \.isHome) else { return }
        let asked = preferredLaps.compactMap { number in home.choices.first { $0.number == number }?.id }
        let quickest = home.choices.sorted { ($0.seconds ?? .infinity) < ($1.seconds ?? .infinity) }.prefix(2)
        chosen =
            asked.isEmpty ? quickest.map(\.id) : Array(NSOrderedSet(array: asked).array.compactMap { $0 as? String })
        rebuild()
    }

    /// The home session's laps `numbers`, in order, the first the reference.
    func choose(_ numbers: [Int]) {
        preferredLaps = numbers
        chooseDefaults()
    }

    // MARK: - Choosing laps

    func isChosen(_ choice: ReplayLapChoice) -> Bool { chosen.contains(choice.id) }
    func isReference(_ choice: ReplayLapChoice) -> Bool { chosen.first == choice.id }
    var isFull: Bool { chosen.count >= LapAnalysis.maximumLaps }

    func toggle(_ choice: ReplayLapChoice) {
        if let index = chosen.firstIndex(of: choice.id) {
            chosen.remove(at: index)
        } else if !isFull {
            chosen.append(choice.id)
        }
        rebuild()
    }

    /// The lap every other is read against.
    func makeReference(_ choice: ReplayLapChoice) {
        guard let index = chosen.firstIndex(of: choice.id), index > 0 else { return }
        chosen.remove(at: index)
        chosen.insert(choice.id, at: 0)
        rebuild()
    }

    /// A chosen lap's colour: its place in the order chosen.
    func color(of choice: ReplayLapChoice) -> Color? { chosen.firstIndex(of: choice.id).map(Self.color) }

    static func color(_ index: Int) -> Color { [Color.blue, .orange, .green, .pink][index % 4] }

    // MARK: - The cursor and the span

    /// Zooms the traces to the corner nearest `distance`, with the cursor on it.
    func zoom(toCornerAt distance: Double) {
        cursor = distance
        guard let analysis, let corner = analysis.corner(at: distance) else { return }
        visible = analysis.zoom(to: corner)
    }

    func zoom(to corner: LapAnalysis.CornerSpan) {
        guard let analysis else { return }
        cursor = corner.apex
        visible = analysis.zoom(to: corner)
    }

    func showWholeLap() { visible = nil }

    // MARK: - The picture

    /// The shown lap and its picture, when it has one.
    private var pictured: (trace: LapAnalysis.Trace, footage: AnalysisFootage)? {
        guard let trace = analysis?.traces.first(where: { $0.id == picture.trace }), let footage = footage[trace.id]
        else { return nil }
        return (trace, footage)
    }

    /// The shown lap's frame at the cursor.
    func showPicture() {
        guard let analysis, let pictured else { return }
        picture.show(pictured.footage, at: analysis.sessionTime(pictured.trace, at: cursor ?? 0))
    }

    /// Plays the shown lap's picture from the cursor, the cursor following it round the lap.
    func playPicture() {
        guard let analysis, let pictured else { return }
        let trace = pictured.trace
        let window = trace.profile.window
        picture.play(pictured.footage, from: analysis.sessionTime(trace, at: cursor ?? 0)) { [weak self] time in
            guard let self, time < window.end else { return false }
            let own = trace.profile.distance(atElapsed: time - window.start)
            self.cursor = own / trace.scale
            return true
        }
    }

    func showPicture(of trace: Int) {
        picture.stop()
        picture.trace = trace
        showPicture()
    }

    // MARK: - Building

    /// Reads in any session a chosen lap needs, then builds the profiles off the main actor.
    func rebuild() {
        generation += 1
        let mine = generation
        isBuilding = true
        let roles = LapAnalysis.roles(adding: layout.channels)
        Task { @MainActor in
            for index in groups.indices
            where groups[index].session == nil && chosen.contains(where: { $0.hasPrefix(groups[index].id + "#") }) {
                guard let entry = groups[index].entry else { continue }
                groups[index].isLoading = true
                let loaded = await LogbookModel.shared.session(for: entry)
                guard generation == mine else { return }
                groups[index].isLoading = false
                groups[index].session = loaded
                if let loaded {
                    groups[index].choices = ReplayModel.completeLaps(of: loaded).map { lap in
                        ReplayLapChoice(
                            id: "\(entry.id.uuidString)#\(lap.number)", groupID: entry.id.uuidString,
                            number: lap.number,
                            seconds: lap.duration)
                    }
                }
            }
            let picks = chosen.compactMap { id -> ReplayPick? in
                guard let group = groups.first(where: { id.hasPrefix($0.id + "#") }),
                    let choice = group.choices.first(where: { $0.id == id })
                else { return nil }
                return ReplayPick(
                    groupID: group.id, title: group.title, subtitle: group.subtitle, session: group.session,
                    number: choice.number, isHome: group.isHome)
            }
            let built = await Task.detached(priority: .userInitiated) { Self.build(picks, roles: roles) }.value
            guard generation == mine else { return }
            let lengthChanged = built?.analysis.length != analysis?.length
            analysis = built?.analysis
            gripTarget = await readGripTarget(for: built?.picks.first)
            guard generation == mine else { return }
            picture.stop()
            footage = await loadFootage(for: built?.picks ?? [])
            guard generation == mine else { return }
            if footage[picture.trace] == nil { picture.trace = footage.keys.min() ?? 0 }
            isBuilding = false
            if lengthChanged {
                visible = nil
                cursor = nil
            }
        }
    }

    /// The analysis, and the picks that made a trace each, in trace order.
    nonisolated static func build(_ picks: [ReplayPick], roles: [ChannelRole]) -> (
        analysis: LapAnalysis, picks: [ReplayPick]
    )? {
        var kept: [ReplayPick] = []
        let profiles = picks.compactMap { pick -> (label: String, profile: LapProfile)? in
            guard let session = pick.session, let lap = session.laps.first(where: { $0.number == pick.number }),
                let end = lap.end,
                let profile = LapProfile(
                    window: .init(start: lap.start, end: end), in: session, label: "Lap \(lap.number)", roles: roles,
                    lapNumber: lap.number)
            else { return nil }
            let label =
                pick.isHome
                ? "Lap \(lap.number)" : "\(pick.subtitle.isEmpty ? pick.title : pick.subtitle) · Lap \(lap.number)"
            kept.append(pick)
            return (label, profile)
        }
        guard let first = kept.first, let session = first.session,
            let lap = session.laps.first(where: { $0.number == first.number }),
            let analysis = LapAnalysis(profiles: profiles, corners: LapAnalysis.corners(of: lap, in: session))
        else { return nil }
        return (analysis, Array(kept.prefix(LapAnalysis.maximumLaps)))
    }
}

// Outside the class's body, which the laps and the picture fill.
extension LapAnalysisModel {
    /// The channels the chosen laps' sessions recorded that can be traced, beside speed.
    var traceableChannels: [ChannelRole] {
        let excluded: Set<ChannelRole> = [.latitude, .longitude, .distance, .speed]
        var seen: [ChannelRole] = []
        for group in groups where group.session != nil && chosen.contains(where: { $0.hasPrefix(group.id + "#") }) {
            for channel in group.session?.orderedChannels ?? [] where !excluded.contains(channel.role) {
                if !seen.contains(channel.role) { seen.append(channel.role) }
            }
        }
        for role in [ChannelRole.lateralG, .longitudinalG] where !seen.contains(role) { seen.append(role) }
        return seen
    }

    /// What a channel's numbers are in, from the reference's session.
    func unit(of role: ChannelRole) -> String {
        switch role {
        case .lateralG, .longitudinalG: return "G"
        default: break
        }
        let session = groups.first { group in chosen.first?.hasPrefix(group.id + "#") ?? false }?.session
        return session?[role]?.unit.symbol ?? ""
    }

    /// The car's grip in the reference lap's conditions, when the logbook knows its session; else
    /// the most that session reached, measured off the main actor.
    private func readGripTarget(for reference: ReplayPick?) async -> GripTarget? {
        guard let reference else { return nil }
        let group = groups.first { $0.id == reference.groupID }
        let entryID =
            group?.entry?.id
            ?? editor?.project.dataInputs.first { $0.id.rawValue.uuidString == reference.groupID }?.dataSettings?
            .logbookEntryID
        let logbook = LogbookModel.shared
        let entry = entryID.flatMap { id in logbook.entries.first { $0.id == id } }
        if let limit = entry.flatMap({ logbook.gripLimit(for: $0) }) { return .car(limit) }
        guard let session = reference.session else { return nil }
        let own = await Task.detached(priority: .userInitiated) { GripEnvelope.measure(session) }.value
        return GripTarget.choose(car: nil, session: own)
    }
}
