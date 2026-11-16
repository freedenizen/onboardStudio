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
    /// Metres into the reference lap the cursor is at.
    var cursor: Double?
    /// The span the traces show; `nil` is the whole lap.
    var visible: ClosedRange<Double>?
    var layout: AnalysisLayout {
        didSet {
            UserDefaults.standard.set(layout.preferenceText, for: Preferences.analysisLayout)
            if layout.channels != oldValue.channels { rebuild() }
        }
    }
    private var generation = 0

    init() {
        layout = AnalysisLayout(preferenceText: UserDefaults.standard.value(for: Preferences.analysisLayout))
    }

    var hasSource: Bool { !groups.isEmpty || isLoading || problem != nil }
    var span: ClosedRange<Double> { visible ?? 0...(analysis?.length ?? 1) }

    // MARK: - Sources

    /// The front project's session with laps, its other data files beside it, and the logbook's
    /// other sessions at the circuit.
    func showFrontProject(editor: EditorModel?) {
        kind = .frontProject
        reset()
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
    func show(entry: LogbookEntry) {
        if case .logbook(let id) = kind, id == entry.id, !groups.isEmpty { return }
        kind = .logbook(entry.id)
        reset()
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
        cursor = nil
        visible = nil
        generation += 1
    }

    /// The home session's best lap as the reference, and its next quickest against it.
    private func chooseDefaults() {
        guard let home = groups.first(where: \.isHome) else { return }
        chosen = home.choices.sorted { ($0.seconds ?? .infinity) < ($1.seconds ?? .infinity) }.prefix(2).map(\.id)
        rebuild()
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
            let lengthChanged = built?.length != analysis?.length
            analysis = built
            isBuilding = false
            if lengthChanged {
                visible = nil
                cursor = nil
            }
        }
    }

    nonisolated static func build(_ picks: [ReplayPick], roles: [ChannelRole]) -> LapAnalysis? {
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
            return (label, profile)
        }
        guard let first = picks.first, let session = first.session,
            let lap = session.laps.first(where: { $0.number == first.number })
        else { return nil }
        return LapAnalysis(profiles: profiles, corners: LapAnalysis.corners(of: lap, in: session))
    }
}
