import Foundation
import Testing

@testable import TelemetryKit

@Suite("Suggesting a start/finish line")
struct StartFinishFinderTests {
    /// The stadium circuit, driven four laps. Its start/finish is the middle of the bottom
    /// straight, which is where a suggestion should land or near it.
    static let geometry = SyntheticTrack.geometry()

    /// The same session with its lap list thrown away, which is what a file with no lap column
    /// looks like: one partial lap covering everything.
    static func withoutLaps(_ session: TelemetrySession) -> TelemetrySession {
        var stripped = session
        let range = session.timeRange
        stripped.laps = [
            Lap(number: 0, start: range?.lowerBound ?? 0, end: range?.upperBound, isComplete: false)
        ]
        return stripped
    }

    @Test func theFilesOwnLapsAreUsedWhenItHasThem() throws {
        let session = SyntheticTrack.session(laps: 4)
        let suggestion = try #require(StartFinishFinder.suggest(in: session))
        #expect(suggestion.source == .fileLaps)
        // The line lands on the start/finish, which the generator puts at the origin.
        #expect(abs(suggestion.line.latitude - SyntheticTrack.origin.latitude) < 1e-4)
        #expect(abs(suggestion.line.longitude - SyntheticTrack.origin.longitude) < 1e-4)
        #expect(suggestion.laps >= 2)
        // A real line gives every lap the same length.
        #expect(suggestion.spread < 0.05)
    }

    @Test func aTraceWithNoLapsStillGetsALine() throws {
        let session = Self.withoutLaps(SyntheticTrack.session(laps: 4))
        let suggestion = try #require(StartFinishFinder.suggest(in: session))
        #expect(suggestion.source == .trace)
        #expect(suggestion.laps >= 2)
        #expect(suggestion.spread < 0.05)
    }

    @Test func theSuggestedLineActuallyDetectsLaps() throws {
        // The point of the whole thing: hand the line straight back to the lap detector and get
        // laps of the right length out.
        let session = Self.withoutLaps(SyntheticTrack.session(laps: 4))
        let suggestion = try #require(StartFinishFinder.suggest(in: session))
        let laps = LapDetector.detect(in: session, line: suggestion.line)
        let complete = laps.filter { $0.isComplete && $0.duration != nil }
        #expect(complete.count >= 2)
        let distance = try #require(session[.distance])
        for lap in complete {
            let length = try #require(LapComparison.length(of: lap, distance: distance))
            #expect(abs(length - Self.geometry.lapLength) < Self.geometry.lapLength * 0.05)
        }
    }

    @Test func aSessionWithoutPositionSuggestsNothing() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [0, 1], values: [10, 10])])
        #expect(StartFinishFinder.suggest(in: session) == nil)
    }

    @Test func oneLapIsNotEnoughToBeConsistentAbout() {
        // A single lap tells you nothing about whether a line repeats.
        let session = Self.withoutLaps(SyntheticTrack.session(laps: 1))
        #expect(StartFinishFinder.suggest(in: session) == nil)
    }

    @Test func spreadFallsBackToLapTimesWithoutADistanceChannel() throws {
        var session = SyntheticTrack.session(laps: 3)
        session.remove(.distance)
        let laps = session.laps.filter { $0.isComplete }
        let spread = StartFinishFinder.spread(of: laps, in: session)
        // The generator drives every lap at the same speed, so the times match too.
        #expect(spread < 0.05)
    }

    @Test func consistencyBeatsLapCount() {
        // A candidate that finds more laps does not win unless it is at least as consistent,
        // which is what stops a line the car crosses twice a lap from being preferred.
        let line = FinishLine(latitude: 0, longitude: 0)
        let consistent = StartFinishFinder.Suggestion(line: line, source: .trace, laps: 4, spread: 0.01)
        let scattered = StartFinishFinder.Suggestion(line: line, source: .trace, laps: 9, spread: 0.6)
        #expect(!StartFinishFinder.isBetter(scattered, than: consistent))
        #expect(StartFinishFinder.isBetter(consistent, than: scattered))
        // Equally consistent, so the one that finds more laps wins after all.
        let same = StartFinishFinder.Suggestion(line: line, source: .trace, laps: 8, spread: 0.015)
        #expect(StartFinishFinder.isBetter(same, than: consistent))
        // With nothing to compare against, anything is an improvement.
        #expect(StartFinishFinder.isBetter(scattered, than: nil))
    }
}
