import Foundation
import Testing

@testable import TelemetryKit

@Suite("Coaching track")
struct CoachingTrackTests {
    /// Fast, slow, fast, fast: every lap read against the best.
    static let session = CoachingFixture.session(drivings: [.init(), CoachingFixture.slow, .init(), .init()])

    @Test func everyCompleteLapIsReadAgainstTheReferenceOnce() throws {
        let track = try #require(CoachingTrack.make(session: Self.session, reference: .sessionBest))
        #expect(track.laps.map(\.number) == [1, 2, 3, 4])
        #expect(track.analyses.count == 4)
        #expect(track.referencePhrase == "your best lap")
        // The slow lap's reading is the one the window and the command line give.
        let slow = try #require(track.analyses[2])
        let direct = try #require(
            CoachingAnalysis.analyse(lap: Self.session.laps[1], reference: .sessionBest, in: Self.session))
        #expect(slow.corners.map(\.timeLost) == direct.corners.map(\.timeLost))
        #expect(slow.opportunities == direct.opportunities)
        #expect(track.analysis(atInputTime: Self.session.laps[1].start + 5)?.lap.number == 2)
        #expect(track.analysis(atInputTime: -1) == nil)
    }

    @Test func theMomentIsTheCornerComingDrivenOrJustLeft() throws {
        let track = try #require(CoachingTrack.make(session: Self.session, reference: .sessionBest))
        let lap = Self.session.laps[1]
        let analysis = try #require(track.analyses[2])
        let first = analysis.corners[0]
        let brakeAt = lap.start + analysis.lap.elapsed(atDistance: first.lap.phaseStart)
        let endAt = lap.start + analysis.lap.elapsed(atDistance: first.lap.corner.endDistance)
        // On the back straight, past the first corner's hold and before the second's lead: nothing.
        let straight = lap.start + analysis.lap.elapsed(atDistance: 490)
        #expect(track.moment(atInputTime: straight, leadSeconds: 3, holdSeconds: 2) == nil)
        // Inside the lead: the corner is coming, with the time to its brake point.
        let coming = try #require(track.moment(atInputTime: brakeAt - 2, leadSeconds: 3, holdSeconds: 2))
        #expect(coming.comparison.index == first.index)
        #expect(coming.phase == nil)
        #expect(!coming.isHeld)
        #expect(abs(coming.secondsToBrakePoint - 2) < 0.05)
        // Braking: in play, in the braking phase.
        let braking = try #require(track.moment(atInputTime: brakeAt + 0.5, leadSeconds: 3, holdSeconds: 2))
        #expect(braking.phase == .braking)
        #expect(braking.secondsToBrakePoint < 0)
        // Just after the corner: held, then gone.
        let held = try #require(track.moment(atInputTime: endAt + 1, leadSeconds: 3, holdSeconds: 2))
        #expect(held.isHeld)
        #expect(held.comparison.index == first.index)
        #expect(track.moment(atInputTime: endAt + 3, leadSeconds: 3, holdSeconds: 2) == nil)
        // The lap number is the one at the moment.
        #expect(braking.lap.number == 2)
    }

    @Test func aReferenceFromAnotherSessionIsReadAcrossSessions() throws {
        let other = LapAlignmentTests.shifted(CoachingFixture.session(drivings: [.init()]), east: 3)
        let reference = try #require(LapProfile(lap: other.laps[0], in: other))
        let track = try #require(
            CoachingTrack.make(
                session: Self.session, reference: reference, referencePhrase: "Alex lap 1", sameSession: false))
        #expect(track.analyses.count == 4)
        #expect(track.analyses[2]?.delta.alignment == .byPosition)
        #expect(track.analyses[2]?.consistency == nil)
        #expect(track.analyses[2]?.referencePhrase == "Alex lap 1")
    }

    @Test func nothingWithoutLapsOrAReference() {
        let empty = TelemetrySession(info: SessionInfo(sourceFormat: "test"), channels: [])
        #expect(CoachingTrack.make(session: empty, reference: .sessionBest) == nil)
        #expect(CoachingTrack.make(session: Self.session, reference: .lap(99)) == nil)
    }
}
