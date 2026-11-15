import Foundation
import Testing

@testable import TelemetryKit

/// Another car's log from the same session (#574): the stretches spent close behind it are
/// measured from the two traces, and become suggestions in the corners they cover.
@Suite("Cars ahead")
struct CarsAheadTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Four identical laps, on the clock: the telemetry alone suggests nothing.
    static func mine(laps: Int = 4) -> TelemetrySession {
        var session = CoachingFixture.session(
            drivings: Array(repeating: CoachingFixture.fast, count: laps), pedals: true)
        session.info.createdAt = start
        return session
    }

    /// Another car on the same circuit, `lead(t)` seconds ahead of `mine` at its time `t`: where
    /// `mine` would be `lead` seconds later. Its log starts `startsLater` seconds after mine, so its
    /// own times are not mine.
    static func other(
        ahead mine: TelemetrySession, startsLater: Double = 100, lead: (Double) -> Double
    ) throws -> TelemetrySession {
        let latitude = try #require(mine[.latitude])
        let longitude = try #require(mine[.longitude])
        let times = latitude.times
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic", createdAt: start.addingTimeInterval(startsLater)),
            channels: [
                Channel(
                    role: .latitude, name: "lat", unit: .degrees, times: times.map { $0 - startsLater },
                    values: times.map { latitude.value(at: $0 + lead($0)) ?? 0 }),
                Channel(
                    role: .longitude, name: "lon", unit: .degrees, times: times.map { $0 - startsLater },
                    values: times.map { longitude.value(at: $0 + lead($0)) ?? 0 }),
            ])
    }

    /// One second ahead through `lap`, dropping back to twenty either side of it as a car that
    /// pulls away does.
    static func close(on lap: Lap, of mine: TelemetrySession) throws -> TelemetrySession {
        let end = try #require(lap.end)
        return try other(ahead: mine) { min(20, 1 + max(0, lap.start - $0, $0 - end) / 2) }
    }

    static func closeOnLapThree(_ mine: TelemetrySession) throws -> TelemetrySession {
        try close(on: mine.laps[2], of: mine)
    }

    @Test func theStretchBehindTheOtherCarIsMeasured() throws {
        let mine = Self.mine()
        let lap = mine.laps[2]
        let ahead = CarsAhead.following(in: mine, behind: try Self.closeOnLapThree(mine), car: "GR86")
        let only = try #require(ahead.count == 1 ? ahead.first : nil)
        #expect(only.car == "GR86")
        #expect(abs(only.closestGap - 1) < 0.05)
        // The whole lap, and the seconds after it until the gap opens past 1.5 s.
        let end = try #require(lap.end)
        #expect(only.window.start <= lap.start + 0.2 && only.window.start >= lap.start - 3.5)
        #expect(only.window.end >= end && only.window.end <= end + 3.5)
    }

    @Test func aCarFarAheadBehindOrOnAnotherClockIsNotFollowed() throws {
        let mine = Self.mine()
        #expect(CarsAhead.following(in: mine, behind: try Self.other(ahead: mine) { _ in 5 }, car: "A").isEmpty)
        #expect(CarsAhead.following(in: mine, behind: try Self.other(ahead: mine) { _ in -1 }, car: "B").isEmpty)
        // The same recording read twice is not a car ahead of itself.
        #expect(CarsAhead.following(in: mine, behind: try Self.other(ahead: mine) { _ in 0 }, car: "C").isEmpty)
        var unanchored = try Self.closeOnLapThree(mine)
        unanchored.info.createdAt = nil
        #expect(CarsAhead.following(in: mine, behind: unanchored, car: "D").isEmpty)
        // A car stopped where this one is driving (the pit lane beside the straight) never is.
        let parked = try Self.other(ahead: mine) { _ in 0.5 }
        let latitude = try #require(mine[.latitude])
        let longitude = try #require(mine[.longitude])
        let stopped = TelemetrySession(
            info: mine.info,
            channels: [
                Channel(
                    role: .latitude, name: "lat", unit: .degrees, times: latitude.times,
                    values: latitude.values.map { _ in latitude.values[0] }),
                Channel(
                    role: .longitude, name: "lon", unit: .degrees, times: longitude.times,
                    values: longitude.values.map { _ in longitude.values[0] }),
            ])
        #expect(CarsAhead.following(in: stopped, behind: parked, car: "E").isEmpty)
    }

    @Test func theCornersCoveredAreSuggestedWithTheCarNamed() throws {
        var mine = Self.mine()
        mine.carsAhead = CarsAhead.following(in: mine, behind: try Self.closeOnLapThree(mine), car: "GR86")
        let corners = CornerDetector.corners(of: try #require(LapProfile(lap: mine.laps[0], in: mine)))
        let suggestions = TrafficSuggestions.find(in: mine, corners: corners)
        #expect(suggestions.map(\.lapNumber) == [3, 3])
        #expect(suggestions.map(\.corner) == [0, 1])
        for suggestion in suggestions {
            guard case .following(let car, let seconds) = suggestion.evidence.first else {
                Issue.record("no car ahead in \(suggestion.evidence)")
                continue
            }
            #expect(car == "GR86")
            #expect(abs(seconds - 1) < 0.05)
            // Driven as every other lap: nothing else to see.
            #expect(suggestion.evidence.count == 1)
        }
    }

    @Test func aCarAheadIsSuggestedWhenTooFewLapsSayWhatIsUsual() throws {
        var mine = Self.mine(laps: 3)
        let other = try Self.close(on: mine.laps[1], of: mine)
        mine.carsAhead = CarsAhead.following(in: mine, behind: other, car: "GR86")
        var options = CoachingOptions()
        options.trafficSuggestions.minimumLaps = 5
        let corners = CornerDetector.corners(of: try #require(LapProfile(lap: mine.laps[0], in: mine)))
        #expect(TrafficSuggestions.find(in: mine, corners: corners, options: options).map(\.lapNumber) == [2, 2])
        mine.carsAhead = []
        #expect(TrafficSuggestions.find(in: mine, corners: corners, options: options).isEmpty)
    }

    @Test func theSentenceNamesTheCar() {
        let suggestion = TrafficSuggestion(
            lapNumber: 3, corner: 2, label: "3", window: .init(start: 10, end: 14),
            evidence: [.following(car: "GR86", seconds: 0.8), .slow(seconds: 1.2)])
        #expect(
            suggestion.sentence(units: .metric)
                == "You were 0.80 s behind the GR86 and Turn 3 took 1.20 s longer than it usually does")
    }

    @Test func carsAheadRoundTrip() throws {
        let ahead = CarAhead(car: "GR86", window: .init(start: 10, end: 14), closestGap: 0.8)
        #expect(try JSONDecoder().decode(CarAhead.self, from: JSONEncoder().encode(ahead)) == ahead)
        let evidence = TrafficSuggestion.Evidence.following(car: "GR86", seconds: 0.8)
        let decoded = try JSONDecoder().decode(TrafficSuggestion.Evidence.self, from: JSONEncoder().encode(evidence))
        #expect(decoded == evidence)
    }
}
