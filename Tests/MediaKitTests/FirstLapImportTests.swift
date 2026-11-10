import Foundation
import ProjectModel
import Testing

@testable import MediaKit

/// #477 through the door a project uses: a data input's settings decide which reading its file
/// gets, so a project saved before keeps its laps and one made since reads the lap where it begins.
@Suite("The first lap of a data input (#477)")
struct FirstLapImportTests {
    /// RaceChrono's CSV v2: the lap column is blank until the first crossing of the line.
    static let csv = TrackDayImportTests.fixtures.appending(path: "racechrono-v2.csv")

    @Test func aNewInputsFirstLapIsAWholeLap() throws {
        let session = try ProjectCompiler.importData(at: Self.csv, settings: DataInputSettings())
        let first = try #require(session.laps.first)
        #expect(first.number == 1 && first.isComplete)
        #expect(first.start > (session.timeRange?.lowerBound ?? 0), "it begins at the crossing, not with the log")
    }

    @Test func aSavedProjectsInputKeepsItIncomplete() throws {
        let session = try ProjectCompiler.importData(at: Self.csv, settings: DataInputSettings(legacyFirstLap: true))
        let first = try #require(session.laps.first)
        #expect(first.number == 1 && !first.isComplete)
        // Nothing else about the laps differs between the two readings.
        let now = try ProjectCompiler.importData(at: Self.csv, settings: DataInputSettings())
        #expect(session.laps.map(\.number) == now.laps.map(\.number))
        #expect(session.laps.map(\.start) == now.laps.map(\.start))
    }
}
