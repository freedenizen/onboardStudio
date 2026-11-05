import Foundation
import ProjectModel
import RenderKit
import TelemetryKit

// Building the replay from the laps chosen (#415): sessions read in as needed, the road and the
// field off the main actor, the scene on it.
extension ReplayModel {
    // MARK: - Building the replay

    /// Reads in any session a chosen lap needs, then builds the road and the field off the main
    /// actor and the scene on it. A later call supersedes an earlier one.
    func rebuild() {
        generation += 1
        let myGeneration = generation
        isBuilding = true
        buildProblem = nil
        Task { @MainActor in
            // Sessions first: a logbook lap's file is read the first time it is chosen.
            for index in groups.indices
            where groups[index].session == nil
                && chosen.contains(where: { $0.hasPrefix(groups[index].id + "#") })
            {
                guard let entry = groups[index].entry else { continue }
                groups[index].isLoading = true
                let loaded = await LogbookModel.shared.session(for: entry)
                guard generation == myGeneration else { return }
                groups[index].isLoading = false
                groups[index].session = loaded
                if let loaded {
                    groups[index].choices = Self.completeLaps(of: loaded).map { lap in
                        ReplayLapChoice(
                            id: "\(entry.id.uuidString)#\(lap.number)", groupID: entry.id.uuidString,
                            number: lap.number, seconds: lap.duration)
                    }
                }
            }
            let picks = chosen.compactMap { id -> (group: ReplaySessionGroup, choice: ReplayLapChoice)? in
                guard let group = groups.first(where: { id.hasPrefix($0.id + "#") }),
                    let choice = group.choices.first(where: { $0.id == id })
                else { return nil }
                return (group, choice)
            }
            guard let homeGroup = groups.first(where: \.isHome), let homeSession = homeGroup.session else {
                finishBuild(nil, problem: nil, generation: myGeneration)
                return
            }
            let cachedTrack = track?.key == homeGroup.id ? track?.model : nil
            let sessions = picks.map {
                ReplayPick(
                    groupID: $0.group.id, title: $0.group.title, subtitle: $0.group.subtitle, session: $0.group.session,
                    number: $0.choice.number, isHome: $0.group.isHome)
            }
            let built = await Task.detached(priority: .userInitiated) { () -> (track: TrackModel, laps: [ReplayLap])? in
                Self.build(home: homeSession, picks: sessions, cachedTrack: cachedTrack)
            }.value
            guard generation == myGeneration else { return }
            guard let built else {
                finishBuild(
                    nil, problem: picks.isEmpty ? nil : "These laps have no position, so there is no road to draw.",
                    generation: myGeneration)
                return
            }
            track = (homeGroup.id, built.track)
            finishBuild(ReplayField(track: built.track, laps: built.laps), problem: nil, generation: myGeneration)
        }
    }

    private func finishBuild(_ field: ReplayField?, problem: String?, generation: Int) {
        guard self.generation == generation else { return }
        isBuilding = false
        buildProblem = problem
        self.field = field
        let keepFollowing = followed.flatMap { id in field?.laps.first { $0.id == id }?.id }
        followed = keepFollowing
        scene = field.map { TrackScene(field: $0) }
        scene?.set(camera: camera, following: followed)
        time = min(time, field?.duration ?? 0)
        scene?.apply(time: time, dt: 1)
    }

    /// The road from the home session's quickest chosen lap (else its best), the laps on it.
    nonisolated static func build(home: TelemetrySession, picks: [ReplayPick], cachedTrack: TrackModel?)
        -> (track: TrackModel, laps: [ReplayLap])?
    {
        let roles = LapProfile.defaultRoles + [.altitude]
        var profiles: [(profile: LapProfile, pick: ReplayPick)] = []
        for pick in picks {
            guard let session = pick.session, let lap = session.laps.first(where: { $0.number == pick.number }),
                let end = lap.end,
                let profile = LapProfile(
                    window: .init(start: lap.start, end: end), in: session, label: "Lap \(lap.number)", stepMeters: 2,
                    roles: roles, lapNumber: lap.number)
            else { continue }
            profiles.append((profile, pick))
        }
        let track: TrackModel
        if let cachedTrack {
            track = cachedTrack
        } else {
            let homeLaps = profiles.filter(\.pick.isHome).map(\.profile)
            let reference =
                homeLaps.min { ($0.elapsed.last ?? .infinity) < ($1.elapsed.last ?? .infinity) }
                ?? Self.bestLapProfile(of: home, roles: roles)
            guard let reference, let made = TrackModel.make(reference: reference, laps: profiles.map(\.profile)) else {
                return nil
            }
            track = made
        }
        let laps = profiles.compactMap { item -> ReplayLap? in
            let seconds = item.profile.elapsed.last ?? 0
            let label = item.pick.isHome ? "Lap \(item.pick.number)" : "\(item.pick.title) lap \(item.pick.number)"
            return ReplayLap(
                profile: item.profile, on: track, id: Self.lapID(item.pick.groupID, item.pick.number),
                label: "\(label) · \(TimeParsing.lapTimeString(seconds, decimals: 2))",
                subtitle: item.pick.isHome ? "" : item.pick.subtitle)
        }
        return (track, laps)
    }

    nonisolated static func bestLapProfile(of session: TelemetrySession, roles: [ChannelRole]) -> LapProfile? {
        guard let best = LapDeltas.sessionBest(in: session), let end = best.end else { return nil }
        return LapProfile(
            window: .init(start: best.start, end: end), in: session, label: "Lap \(best.number)", stepMeters: 2,
            roles: roles, lapNumber: best.number)
    }

    /// A stable id for a lap of a group, so following it survives a rebuild.
    nonisolated static func lapID(_ groupID: String, _ number: Int) -> UUID {
        var hasher = Hasher()
        hasher.combine(groupID)
        hasher.combine(number)
        let value = UInt64(bitPattern: Int64(hasher.finalize()))
        return UUID(
            uuid: (
                UInt8(value >> 56 & 0xff), UInt8(value >> 48 & 0xff), UInt8(value >> 40 & 0xff),
                UInt8(value >> 32 & 0xff),
                UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff),
                0x52, 0x45, 0x50, 0x4c, 0x41, 0x59, UInt8(number & 0xff), UInt8(groupID.count & 0xff)
            ))
    }

    /// The choice id a replay lap came from.
    func choice(of lap: ReplayLap) -> ReplayLapChoice? {
        for group in groups {
            if let choice = group.choices.first(where: { Self.lapID(group.id, $0.number) == lap.id }) { return choice }
        }
        return nil
    }
}
