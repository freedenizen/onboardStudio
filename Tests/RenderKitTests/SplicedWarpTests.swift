import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

@Suite("Spliced lap warp")
struct SplicedWarpTests {
    /// The coaching fixture with four equal sectors, so the optimal lap is spliced at each apex.
    static let session: TelemetrySession = {
        var session = CoachingTrackSession.session
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 4), session: session)
        return session
    }()

    @Test func theOptimalLapsPictureIsCutFromTheLapsItCameFrom() throws {
        let session = Self.session
        let optimal = try #require(CoachingReference.compositeOptimal.resolve(in: session))
        #expect(optimal.isSpliced)
        let slow = session.laps[1]
        let warp = try #require(
            LapTimeWarp(
                lap: slow, in: session, sync: .identity, splice: optimal, in: session, comparedSync: .identity))
        // Knots strictly increase along the lap playing; the compared side jumps at each seam.
        #expect(zip(warp.lapTimes, warp.lapTimes.dropFirst()).allSatisfy { $0 < $1 })
        let jumps = zip(warp.comparedTimes, warp.comparedTimes.dropFirst()).filter { abs($1 - $0) > 5 }.count
        #expect(jumps >= optimal.seams.count, "\(jumps) jumps for \(optimal.seams.count) seams")
        // Inside each piece, the compared moment is the source lap's own time at that distance.
        let distance = try #require(session[.distance])
        let slowStart = try #require(distance.value(at: slow.start))
        let slowLength = try #require(LapComparison.length(of: slow, distance: distance))
        for fraction in [0.1, 0.4, 0.6, 0.9] {
            let spliceDistance = fraction * optimal.lengthMeters
            let piece = try #require(optimal.piece(at: spliceDistance))
            let source = try #require(session.laps.first { $0.number == piece.lapNumber })
            let sourceStart = try #require(distance.value(at: source.start))
            let expected = try #require(
                LapComparison.time(
                    atDistance: sourceStart + piece.sourceDistance(at: spliceDistance), in: distance,
                    between: source.start, and: source.end ?? source.start))
            let lapTime = try #require(
                LapComparison.time(
                    atDistance: slowStart + fraction * slowLength, in: distance, between: slow.start,
                    and: slow.end ?? slow.start))
            let compared = warp.comparedTime(at: lapTime)
            #expect(abs(compared - expected) < 0.3, "at \(fraction): \(compared) vs \(expected)")
        }
        // The rolling lap works the same way, from the settings.
        let input = Input(label: "Data", source: MediaReference(path: "/tmp/d.csv"), kind: .data(DataInputSettings()))
        let camera = Input(label: "Cam", source: MediaReference(path: "/tmp/c.mp4"), kind: .video(VideoInputSettings()))
        let project = Project(inputs: [camera, input])
        let settings = LapComparisonSettings(
            lap: .init(dataInputID: input.id, videoInputID: camera.id, lap: slow.number),
            comparedLap: .init(dataInputID: input.id, videoInputID: camera.id, lap: slow.number),
            comparedSplice: .fastestRolling)
        let rolling = try #require(LapTimeWarp(settings, project: project, sessions: [input.id: session]))
        #expect(rolling.lapTimes.count > 10)
        #expect(abs(rolling.lapStart - slow.start) < 1e-6)
        // Without the splice the same settings name the lap against itself, which is still a warp.
        var plain = settings
        plain.comparedSplice = nil
        #expect(LapTimeWarp(plain, project: project, sessions: [input.id: session]) != nil)
    }
}
