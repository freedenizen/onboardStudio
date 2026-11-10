import Foundation
import MediaKit
import ProjectModel
import RenderKit
import SwiftUI
import TelemetryKit

/// Where the Replay window's laps come from (#415): the front project's session, or one logbook
/// session — the `CoachingTarget` pattern.
enum ReplaySourceKind: Hashable {
    case frontProject
    case logbook(UUID)
}

/// A lap on offer in the Replay window's list: one of a session's complete laps.
struct ReplayLapChoice: Identifiable, Hashable, Sendable {
    /// "<group>#<lap number>".
    let id: String
    let groupID: String
    let number: Int
    let seconds: Double?

    var title: String { "Lap \(number)" + (seconds.map { " · \(TimeParsing.lapTimeString($0, decimals: 2))" } ?? "") }
}

/// A session whose laps are on offer: the home session first, then the project's other data
/// files or the logbook's other sessions at the circuit, read in when a lap of theirs is chosen.
struct ReplaySessionGroup: Identifiable, Sendable {
    let id: String
    var title: String
    var subtitle: String
    var session: TelemetrySession?
    var entry: LogbookEntry?
    var choices: [ReplayLapChoice]
    var isLoading = false
    var isHome: Bool
}

/// One chosen lap, with the session it comes from, on its way to being built.
struct ReplayPick: Sendable {
    let groupID: String
    let title: String
    let subtitle: String
    let session: TelemetrySession?
    let number: Int
    let isHome: Bool
}

/// What the HUD reads for the watched car.
struct ReplayHUD: Equatable {
    let speed: String
    let lapTime: String
    let gap: String
}

/// The Replay window's state (#415): which session is home, which laps are chosen, the replay
/// built from them, and the clock that drives it. One instance, as the window is one.
@MainActor @Observable final class ReplayModel {
    static let shared = ReplayModel()

    private(set) var kind: ReplaySourceKind = .frontProject
    var groups: [ReplaySessionGroup] = []
    private(set) var chosen: [String] = []
    private(set) var problem: String?
    private(set) var isLoading = false
    var isBuilding = false
    var field: ReplayField?
    var scene: TrackScene?
    /// Why the laps chosen made no replay, when they did not.
    var buildProblem: String?

    var time: Double = 0
    var isPlaying = false
    var rate: Double = 1
    var camera: ReplayCamera = .chase {
        didSet { scene?.set(camera: camera, following: followed) }
    }
    var followed: UUID? {
        didSet { scene?.set(camera: camera, following: followed) }
    }

    var track: (key: String, model: TrackModel)?
    var generation = 0

    var hasSource: Bool { !groups.isEmpty || isLoading || problem != nil }
    var duration: Double { field?.duration ?? 0 }
    var standings: [ReplayField.Standing] { field?.standings(at: time) ?? [] }

    /// The car the camera watches: the followed lap, else the leader.
    var watched: ReplayField.Standing? {
        let standings = standings
        if let followed { return standings.first { $0.lap.id == followed } }
        return standings.first
    }

    // MARK: - Sources

    /// The front project's session with laps, its other data files beside it.
    func showFrontProject(editor: EditorModel?) {
        kind = .frontProject
        reset()
        guard let editor, let input = editor.lapInput, let session = editor.sessions[input.id] else {
            problem = editor == nil ? nil : "The project has no data file with laps."
            return
        }
        var groups = [
            Self.group(
                id: input.id.rawValue.uuidString, title: input.label, subtitle: "", session: session, isHome: true)
        ]
        for other in editor.project.dataInputs where other.id != input.id {
            guard let otherSession = editor.sessions[other.id] else { continue }
            groups.append(
                Self.group(
                    id: other.id.rawValue.uuidString, title: other.label, subtitle: "", session: otherSession,
                    isHome: false))
        }
        let key = LogbookReferences.circuitKey(for: input, session: session, url: editor.dataFileURL(of: input))
        let own = input.dataSettings?.logbookEntryID.flatMap { id in LogbookModel.shared.entries.first { $0.id == id } }
        groups += logbookGroups(at: key, excluding: own?.file.contentHash)
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
            var groups = [
                Self.group(
                    id: entry.id.uuidString, title: entry.title, subtitle: Self.subtitle(of: entry), session: session,
                    entry: entry, isHome: true)
            ]
            groups += logbookGroups(at: key, excluding: entry.file.contentHash)
            self.groups = groups
            isLoading = false
            chooseDefaults()
        }
    }

    private func reset() {
        groups = []
        chosen = []
        problem = nil
        buildProblem = nil
        field = nil
        scene = nil
        time = 0
        isPlaying = false
        followed = nil
        generation += 1
    }

    /// The logbook's other sessions at the circuit, their laps from the entries until read in.
    private func logbookGroups(at circuitKey: String, excluding ownHash: String?) -> [ReplaySessionGroup] {
        LogbookReferences.sessions(at: circuitKey, in: LogbookModel.shared.entries, excluding: ownHash).map { entry in
            let choices = entry.laps.filter(\.isComplete).map { lap in
                ReplayLapChoice(
                    id: "\(entry.id.uuidString)#\(lap.number)", groupID: entry.id.uuidString, number: lap.number,
                    seconds: lap.seconds)
            }
            return ReplaySessionGroup(
                id: entry.id.uuidString, title: entry.title, subtitle: Self.subtitle(of: entry), session: nil,
                entry: entry,
                choices: choices, isHome: false)
        }
    }

    private static func group(
        id: String, title: String, subtitle: String, session: TelemetrySession, entry: LogbookEntry? = nil, isHome: Bool
    ) -> ReplaySessionGroup {
        let choices = completeLaps(of: session).map { lap in
            ReplayLapChoice(id: "\(id)#\(lap.number)", groupID: id, number: lap.number, seconds: lap.duration)
        }
        return ReplaySessionGroup(
            id: id, title: title, subtitle: subtitle, session: session, entry: entry, choices: choices, isHome: isHome)
    }

    /// "23 Aug 2026 · Miata".
    static func subtitle(of entry: LogbookEntry) -> String {
        [entry.date.map { $0.formatted(date: .abbreviated, time: .omitted) }, entry.car.isEmpty ? nil : entry.car]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func completeLaps(of session: TelemetrySession) -> [Lap] {
        LapDeltas.demotingShortLaps(session.laps, distance: session[.distance]).filter {
            $0.isComplete && $0.end != nil
        }
    }

    /// The home session's three quickest laps, to begin with.
    private func chooseDefaults() {
        guard let home = groups.first(where: \.isHome) else { return }
        let quickest = home.choices.sorted { ($0.seconds ?? .infinity) < ($1.seconds ?? .infinity) }.prefix(3)
        chosen = quickest.map(\.id)
        rebuild()
    }

    // MARK: - Choosing laps

    func isChosen(_ choice: ReplayLapChoice) -> Bool { chosen.contains(choice.id) }

    func toggle(_ choice: ReplayLapChoice) {
        if let index = chosen.firstIndex(of: choice.id) {
            chosen.remove(at: index)
        } else {
            chosen.append(choice.id)
        }
        rebuild()
    }

    /// The colour a chosen lap is drawn in: its place in the order chosen.
    func color(of choice: ReplayLapChoice) -> RGBAColor? {
        chosen.firstIndex(of: choice.id).map { ReplayStyle().color(forLap: $0) }
    }

    // MARK: - The clock

    /// Advances the replay by `dt` seconds of wall time while playing, and moves the scene.
    func tick(dt: Double) {
        guard let scene else { return }
        if isPlaying {
            time += dt * rate
            if time >= duration {
                time = duration
                isPlaying = false
            }
        }
        scene.apply(time: time, dt: dt)
    }

    func togglePlaying() {
        if !isPlaying, time >= duration { time = 0 }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        time = min(max(seconds, 0), duration)
        scene?.apply(time: time, dt: 1)
    }

    func goToCorner(_ index: Int) {
        guard let seconds = scene?.time(toCorner: index) else { return }
        seek(to: seconds)
    }

    func step(by seconds: Double) { seek(to: time + seconds) }

    /// The free camera dragged: yaw and pitch by pixels.
    func orbit(byX dx: Float, y dy: Float) {
        guard let scene else { return }
        if camera != .free { camera = .free }
        scene.orbit.yaw -= dx * 0.01
        scene.orbit.pitch = min(max(scene.orbit.pitch + dy * 0.01, 0.05), .pi / 2 - 0.05)
    }

    func zoom(by delta: Float) {
        guard let scene else { return }
        if camera != .free { camera = .free }
        scene.orbit.distance = min(max(scene.orbit.distance * (1 + delta * 0.02), 5), 2_000)
    }

    // MARK: - What the HUD says

    /// Speed in the app's unit, the lap time and the gap for the watched car.
    func hud(speedUnit: SpeedDisplayUnit) -> ReplayHUD? {
        guard let watched else { return nil }
        let metresPerSecond = watched.lap.profile.value(of: .speed, atDistance: watched.distance) ?? 0
        let speed = speedUnit.text(metersPerSecond: metresPerSecond)
        let lapTime = TimeParsing.lapTimeString(min(time, watched.lap.lapTime), decimals: 2)
        let gap = watched.gapSeconds > 0 ? "+\(String(format: "%.2f", watched.gapSeconds))" : "leading"
        return ReplayHUD(speed: speed, lapTime: lapTime, gap: gap)
    }
}
