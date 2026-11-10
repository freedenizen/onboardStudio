import Foundation
import Testing

@testable import TelemetryKit

/// #477: one RaceChrono session read from its archive and from its CSV had a different first lap.
/// The archive says where every lap began, and the first begins at the first crossing of the line;
/// read from the start of the data it swallowed the out-lap. The CSV's lap column is blank until
/// that crossing, and the lap that starts there was called incomplete because it is numbered 1.
@Suite("The first lap (#477)")
struct FirstLapTests {
    /// Eleven seconds of data, one sample a second, with a lap column and markers if given.
    func table(lapValues: [Double?]? = nil, markers: [RawLapMarker] = []) -> RawTable {
        var columns = [RawColumn(name: "RPM", suggestedRole: .rpm, values: Array(repeating: 3_000, count: 11))]
        if let lapValues {
            columns.append(RawColumn(name: "Lap", unit: .count, suggestedRole: .lap, values: lapValues))
        }
        return RawTable(
            info: SessionInfo(sourceFormat: "test"), times: Array(stride(from: 0.0, through: 10, by: 1)),
            columns: columns,
            lapMarkers: markers)
    }

    /// Laps as (number, start, end, complete), which is all these tests ask about.
    func laps(_ table: RawTable, _ options: SessionBuilder.Options = .init()) -> [String] {
        SessionBuilder.build(table, options: options).laps.map {
            "\($0.number): \($0.start)–\($0.end.map { "\($0)" } ?? "?") \($0.isComplete ? "complete" : "partial")"
        }
    }

    // MARK: - Markers that say where the lap began

    /// The out-lap runs to the first crossing at 2 s; laps 1 and 2 are whole; lap 3 is cut off.
    static let archive = [
        RawLapMarker(number: 1, time: 5, start: 2), RawLapMarker(number: 2, time: 8, start: 5),
    ]

    @Test func aLapBeginsWhereTheFileSaysItDid() {
        #expect(
            laps(table(markers: Self.archive)) == [
                "1: 2.0–5.0 complete", "2: 5.0–8.0 complete", "3: 8.0–10.0 partial",
            ])
    }

    @Test func aProjectSavedBeforeKeepsTheLapThatSwallowedTheOutLap() {
        #expect(
            laps(table(markers: Self.archive), .init(legacyFirstLap: true)) == [
                "1: 0.0–5.0 complete", "2: 5.0–8.0 complete", "3: 8.0–10.0 partial",
            ])
    }

    @Test func markersThatOnlyEndLapsReadAsTheyAlwaysDid() {
        // RaceRender's `# Lap N:` tags: a lap begins where the one before ended, the first with the data.
        let ends = [RawLapMarker(number: 0, time: 5), RawLapMarker(number: 1, time: 8)]
        let expected = ["0: 0.0–5.0 complete", "1: 5.0–8.0 complete", "2: 8.0–10.0 partial"]
        #expect(laps(table(markers: ends)) == expected)
        #expect(laps(table(markers: ends), .init(legacyFirstLap: true)) == expected)
    }

    @Test func aLapWhoseStartWasTrimmedAwayIsNotAWholeLap() {
        // Trimmed to begin at 3 s, inside lap 1: what is left of it begins with the data.
        #expect(
            laps(table(markers: Self.archive), .init(trimStart: 3)) == [
                "1: 3.0–5.0 partial", "2: 5.0–8.0 complete", "3: 8.0–10.0 partial",
            ])
        // Trimmed inside the out-lap: lap 1 still begins at its crossing, and is whole.
        #expect(laps(table(markers: Self.archive), .init(trimStart: 1)).first == "1: 2.0–5.0 complete")
    }

    @Test func aGapBetweenLapsIsNotPartOfTheNextOne() {
        // The logger was paused between laps 1 and 2: lap 2 begins where it says, not at 5 s.
        let paused = [RawLapMarker(number: 1, time: 5, start: 2), RawLapMarker(number: 2, time: 9, start: 6)]
        #expect(laps(table(markers: paused)).prefix(2) == ["1: 2.0–5.0 complete", "2: 6.0–9.0 complete"])
    }

    // MARK: - A lap column

    /// Blank until the first crossing at 2 s, as RaceChrono writes it; then laps 1, 2 and 3.
    static let blankThenNumbered: [Double?] = [nil, nil, 1, 1, 1, 2, 2, 2, 3, 3, 3]

    @Test func aLapColumnThatIsBlankUntilItsFirstNumberStartsAtALap() {
        #expect(
            laps(table(lapValues: Self.blankThenNumbered)) == [
                "1: 2.0–5.0 complete", "2: 5.0–8.0 complete", "3: 8.0–10.0 partial",
            ])
    }

    @Test func aProjectSavedBeforeKeepsThatLapIncomplete() {
        #expect(
            laps(table(lapValues: Self.blankThenNumbered), .init(legacyFirstLap: true)) == [
                "1: 2.0–5.0 partial", "2: 5.0–8.0 complete", "3: 8.0–10.0 partial",
            ])
    }

    @Test func aLapColumnNumberedFromTheFirstRowStillStartsMidLap() {
        // An export that begins part-way through lap 4: nothing says where that lap started.
        let midLap: [Double?] = [4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7]
        #expect(laps(table(lapValues: midLap)).first == "4: 0.0–3.0 partial")
        // And one that counts the out-lap as lap 0 reads as it always did.
        let fromZero: [Double?] = [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3]
        #expect(laps(table(lapValues: fromZero)).prefix(2) == ["0: 0.0–2.0 complete", "1: 2.0–5.0 complete"])
    }

    @Test func trimmedIntoTheFirstLapItIsIncompleteAgain() {
        // The column begins with the data once the blank rows and the lap's start are cut away.
        #expect(laps(table(lapValues: Self.blankThenNumbered), .init(trimStart: 3)).first == "1: 3.0–5.0 partial")
    }

    /// The two files of one session now read alike: the point of the issue.
    @Test func theArchiveAndTheCsvOfOneSessionReadAlike() {
        #expect(laps(table(markers: Self.archive)) == laps(table(lapValues: Self.blankThenNumbered)))
    }
}
