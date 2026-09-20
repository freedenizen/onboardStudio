import Testing

@testable import TelemetryKit

@Suite("Trimming a data session")
struct SessionTrimTests {
    /// Ten seconds at 1 Hz, with a lap marker every four seconds.
    private func table() -> RawTable {
        let times = (0...10).map(Double.init)
        let speed = RawColumn(
            name: "KPH", unit: .kilometersPerHour, suggestedRole: .speed,
            values: times.map { 36 + $0 * 3.6 })
        return RawTable(
            info: SessionInfo(sourceFormat: "test"), times: times, columns: [speed],
            lapMarkers: [
                RawLapMarker(number: 1, time: 0), RawLapMarker(number: 2, time: 4),
                RawLapMarker(number: 3, time: 8),
            ])
    }

    @Test func noTrimKeepsEverything() throws {
        let session = SessionBuilder.build(table())
        let speed = try #require(session[.speed])
        #expect(speed.times.count == 11)
        #expect(session.timeRange?.lowerBound == 0 && session.timeRange?.upperBound == 10)
    }

    /// The file's own timebase survives a trim: a trimmed session's times still read as seconds
    /// into the original file, so sync, markers and anything else pointing into it keep pointing
    /// at the same moments.
    @Test func trimmingKeepsTheFilesTimebase() throws {
        let options = SessionBuilder.Options(trimStart: 3, trimEnd: 7)
        let session = SessionBuilder.build(table(), options: options)
        let speed = try #require(session[.speed])

        #expect(speed.times == [3, 4, 5, 6, 7], "not renumbered from zero")
        #expect(session.timeRange?.lowerBound == 3)
        #expect(session.timeRange?.upperBound == 7)
    }

    @Test func eitherEndCanBeLeftOpen() throws {
        let fromFive = SessionBuilder.build(table(), options: .init(trimStart: 5))
        #expect(try #require(fromFive[.speed]).times == [5, 6, 7, 8, 9, 10])

        let toFive = SessionBuilder.build(table(), options: .init(trimEnd: 5))
        #expect(try #require(toFive[.speed]).times == [0, 1, 2, 3, 4, 5])
    }

    /// The reason the trim is applied before anything else: a trimmed-away out-lap must not be
    /// counted, or it would become lap 1 and compete for the best lap.
    /// The reason the trim is applied before anything else: a trimmed-away out-lap must not be
    /// counted, or it would become lap 1 and compete for the best lap.
    @Test func lapsAreDetectedFromWhatIsLeft() {
        let whole = SessionBuilder.build(table())
        #expect(whole.laps.map(\.number) == [2, 3, 4], "markers at 0, 4 and 8 bound three laps plus the tail")

        let trimmed = SessionBuilder.build(table(), options: .init(trimStart: 4))
        #expect(trimmed.laps.map(\.number) == [3, 4], "the lap before the trim is gone, not renumbered")
        #expect(trimmed.laps.first?.start == 4, "and no lap starts before the data does")
    }

    /// A lap that began before the data did would be drawn stretching off the front of the
    /// timeline. This was latent for any file whose first sample is not at t=0.
    @Test func noLapStartsBeforeTheData() {
        let late = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [100, 101, 102, 103],
            columns: [
                RawColumn(name: "KPH", unit: .kilometersPerHour, suggestedRole: .speed, values: [36, 40, 44, 48])
            ],
            lapMarkers: [RawLapMarker(number: 1, time: 102)])
        let session = SessionBuilder.build(late)
        #expect(session.laps.first?.start == 100, "not 0")
    }

    /// Nonsense input must not produce an empty or scrambled session.
    @Test func aBackwardsOrEmptyTrimIsIgnored() throws {
        let backwards = SessionBuilder.build(table(), options: .init(trimStart: 8, trimEnd: 2))
        #expect(try #require(backwards[.speed]).times.count == 11, "a backwards trim keeps everything")

        let outside = SessionBuilder.build(table(), options: .init(trimStart: 100))
        #expect(outside[.speed]?.times.isEmpty ?? true, "a trim past the end leaves nothing")
    }

    /// Trimming to a single instant is degenerate but must not trap.
    @Test func aTrimToOneInstantDoesNotTrap() throws {
        let session = SessionBuilder.build(table(), options: .init(trimStart: 5, trimEnd: 5))
        #expect(try #require(session[.speed]).times == [5])
    }
}
