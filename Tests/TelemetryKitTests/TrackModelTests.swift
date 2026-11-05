import Foundation
import Testing

@testable import TelemetryKit

@Suite("Track model and replay laps (#413)")
struct TrackModelTests {
    static let geometry = SyntheticTrack.geometry()
    static let session = SyntheticTrack.session(laps: 3)

    static func profile(_ lap: Int, in session: TelemetrySession = session) throws -> LapProfile {
        let end = try #require(session.laps[lap].end)
        return try #require(
            LapProfile(
                window: .init(start: session.laps[lap].start, end: end), in: session, label: "Lap \(lap + 1)",
                roles: LapProfile.defaultRoles + [.altitude], lapNumber: lap + 1))
    }

    @Test func theRoadFollowsTheReferenceLapRoundTheLoop() throws {
        let reference = try Self.profile(0)
        let track = try #require(TrackModel.make(reference: reference))
        #expect(abs(track.lengthMeters - Self.geometry.lapLength) < track.stepMeters * 2)
        #expect(track.samples.count == Int(track.lengthMeters / track.stepMeters))
        #expect(!track.hasElevation, "the synthetic logger records no altitude")
        #expect(track.samples.allSatisfy { $0.position.z == 0 })
        // The start/finish sits mid-straight heading east; the loop closes on itself.
        let first = track.samples[0]
        #expect(abs(first.heading - 90) < 3)
        let last = try #require(track.samples.last)
        let gap = first.point - last.point
        #expect(sqrt(gap.x * gap.x + gap.y * gap.y) < track.stepMeters * 1.5)
        // The plane is centred on the track and round-trips.
        let back = track.plane.coordinate(at: first.point)
        #expect(abs(back.latitude - (reference.latitude?[0] ?? 0)) < 1e-7)
        #expect(abs(back.longitude - (reference.longitude?[0] ?? 0)) < 1e-7)
        // One lap, no other line: the default width everywhere on the straights.
        #expect(abs(first.halfWidth - TrackModel.Options().defaultHalfWidth) < 0.01)
        // Two bends, kerbs only inside them.
        #expect(track.corners.count == 2)
        for (index, sample) in track.samples.enumerated() {
            let distance = Double(index) * track.stepMeters
            let inCorner = track.corners.contains { distance >= $0.startDistance - 1 && distance <= $0.endDistance + 1 }
            if !inCorner { #expect(!sample.kerbLeft && !sample.kerbRight, "kerb on a straight at \(distance) m") }
        }
        #expect(track.samples.contains { $0.kerbLeft } && track.samples.contains { $0.kerbRight })
        // A right-hander: the inside (right) kerb before the apex, the outside (left) after it.
        let apex = track.corners[0].apexDistance
        #expect(track.sample(atDistance: apex - 30).kerbRight && !track.sample(atDistance: apex - 30).kerbLeft)
        #expect(track.sample(atDistance: apex + 30).kerbLeft && !track.sample(atDistance: apex + 30).kerbRight)
    }

    @Test func samplingWrapsAndNearestFindsTheRoad() throws {
        let track = try #require(TrackModel.make(reference: try Self.profile(0)))
        let wrapped = track.sample(atDistance: track.lengthMeters + 10)
        let plain = track.sample(atDistance: 10)
        #expect(abs(wrapped.position.x - plain.position.x) < 1e-6 && abs(wrapped.heading - plain.heading) < 1e-6)
        let half = track.sample(atDistance: track.stepMeters / 2)
        #expect(abs(half.position.x - (track.samples[0].position.x + track.samples[1].position.x) / 2) < 1e-6)
        // A grid point is found at its own distance; a point to its right reads as right of the road.
        let at = 120.0
        let sample = track.sample(atDistance: at)
        let found = track.nearest(to: sample.point)
        #expect(abs(found.distance - at) < 0.5 && abs(found.lateral) < 0.01)
        // Heading east on the bottom straight: right is south (−north).
        let right = track.nearest(to: sample.point + SIMD2(0, -3))
        #expect(abs(right.lateral - 3) < 0.05 && abs(right.distance - at) < 0.5)
        let left = track.nearest(to: sample.point + SIMD2(0, 3))
        #expect(abs(left.lateral + 3) < 0.05)
        // Far off the circuit still answers, with the nearest piece of road.
        _ = track.nearest(to: SIMD2(5_000, 5_000))
    }

    @Test func anotherLineWidensTheRoadAndAltitudeGivesItHills() throws {
        // A second session on the same circuit driven 4 m to the north of the first: the road
        // must be wide enough for both lines.
        let shifted = Self.shifted(Self.session, north: 4)
        let reference = try Self.profile(0)
        let other = try Self.profile(0, in: shifted)
        let track = try #require(TrackModel.make(reference: reference, laps: [reference, other]))
        let straight = track.sample(atDistance: 100)
        #expect(straight.halfWidth > 5.9, "4 m of spread plus the margin: \(straight.halfWidth)")
        #expect(straight.halfWidth <= TrackModel.Options().halfWidthRange.upperBound)
        // The bends hold the width down to what their radius allows.
        #expect(track.samples.allSatisfy { $0.halfWidth >= 2 })

        // Altitude: a gentle hill once a lap, recorded with noise, comes out smooth and closed.
        let hilly = Self.withAltitude(Self.session)
        let hillyReference = try Self.profile(0, in: hilly)
        let hills = try #require(TrackModel.make(reference: hillyReference))
        #expect(hills.hasElevation)
        let ups = hills.samples.map(\.position.z)
        #expect(ups.min() == 0, "the lowest point reads as 0 up")
        #expect((ups.max() ?? 0) > 6, "a 10 m hill survives the smoothing: \(ups.max() ?? 0)")
        #expect(abs(ups[0] - ups[ups.count - 1]) < 0.5, "the loop closes")
        // Smooth: no step between neighbours bigger than the slope could make.
        for index in 1..<ups.count { #expect(abs(ups[index] - ups[index - 1]) < 0.5) }
    }

    @Test func lapsRaceEachOtherFromTheLine() throws {
        let quick = SyntheticTrack.session(speed: 30, laps: 1)
        let slow = SyntheticTrack.session(speed: 25, laps: 1)
        let reference = try Self.profile(0, in: quick)
        let track = try #require(TrackModel.make(reference: reference))
        let fast = try #require(ReplayLap(profile: reference, on: track, label: "Fast"))
        let slowProfile = try Self.profile(0, in: slow)
        let steady = try #require(ReplayLap(profile: slowProfile, on: track, label: "Steady"))
        #expect(fast.points.count == reference.count)
        #expect(fast.points.allSatisfy { abs($0.z - 0.05) < 1e-9 }, "on the road, a touch above it")
        let start = fast.position(atElapsed: 0)
        #expect(start.distance == 0 && abs(start.heading - 90) < 3)
        let later = fast.position(atElapsed: 10)
        #expect(abs(later.distance - 300) < 5, "30 m/s for 10 s")
        #expect(fast.position(atElapsed: 1_000).distance == reference.lengthMeters, "home, and waiting")

        let field = ReplayField(track: track, laps: [steady, fast])
        #expect(abs(field.duration - steady.lapTime) < 1e-9)
        let standings = field.standings(at: 10)
        #expect(standings.map(\.lap.label) == ["Fast", "Steady"])
        #expect(standings[0].gapSeconds == 0)
        // The slower car is 50 m back, which the leader covered in 50/30 s.
        #expect(abs(standings[1].gapSeconds - 50.0 / 30.0) < 0.1, "\(standings[1].gapSeconds)")
        let home = field.standings(at: field.duration + 1)
        #expect(home.allSatisfy { $0.finished })
        #expect(abs(home[1].gapSeconds - (steady.lapTime - fast.lapTime)) < 1e-6)
        // Jumping to a turn lands a little before its apex.
        let turn = try #require(field.time(toCorner: 0, following: fast.id))
        #expect(abs(fast.position(atElapsed: turn + 3).distance - track.corners[0].apexDistance) < 2)
        #expect(field.time(toCorner: 7) == nil)
    }

    // MARK: - Fixtures

    /// The same session with every position moved `north` metres.
    static func shifted(_ session: TelemetrySession, north: Double) -> TelemetrySession {
        let channels = session.channels.values.map { channel -> Channel in
            guard channel.role == .latitude else { return channel }
            return Channel(
                role: channel.role, name: channel.name, unit: channel.unit, times: channel.times,
                values: channel.values.map { $0 + north / LocalPlane.metersPerDegreeLatitude },
                interpolation: channel.interpolation)
        }
        return TelemetrySession(info: session.info, channels: channels, laps: session.laps)
    }

    /// The same session with a 10 m hill once a lap and a metre of GPS noise on it.
    static func withAltitude(_ session: TelemetrySession) -> TelemetrySession {
        guard let distance = session[.distance] else { return session }
        var noise = 12_345
        let values = distance.values.map { metres -> Double in
            noise = (noise &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff
            let jitter = Double(noise % 2_000) / 1_000 - 1
            let lap = geometry.lapLength
            return 150 + 5 + 5 * sin(2 * .pi * metres / lap) + jitter
        }
        let altitude = Channel(
            role: .altitude, name: "Altitude", unit: .meters, times: distance.times, values: values,
            interpolation: distance.interpolation)
        return TelemetrySession(
            info: session.info, channels: Array(session.channels.values) + [altitude], laps: session.laps)
    }
}
