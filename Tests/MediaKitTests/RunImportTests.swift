import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #552 through the door a project uses: a VBO file that carries a start and a finish gate is a
/// point-to-point course, and a data input with both lines is timed in runs.
@Suite("Runs of a point-to-point course (#552)")
struct RunImportTests {
    static let vbo = TrackDayImportTests.fixtures.appending(path: "autocross.vbo")

    /// The settings `EditorModel.applyLapGeometry` writes for a file just added.
    static func settings(runs: Bool) throws -> DataInputSettings {
        let geometry = try ProjectCompiler.importData(at: vbo, settings: DataInputSettings()).lapGeometry
        let start = try #require(geometry.start)
        let finish = try #require(geometry.finish)
        func line(_ gate: LapGate) -> LapLineSpec {
            LapLineSpec(
                latitude: gate.centreLatitude, longitude: gate.centreLongitude, halfWidthMeters: gate.halfWidthMeters)
        }
        return DataInputSettings(lapLine: line(start), runFinishLine: runs ? line(finish) : nil)
    }

    @Test func theFilesGatesTimeItInRuns() throws {
        let session = try ProjectCompiler.importData(at: Self.vbo, settings: try Self.settings(runs: true))
        let runs = session.laps.listed
        #expect(session.laps.areRuns)
        #expect(runs.map(\.number) == [1, 2, 3])
        #expect(runs.map(\.isComplete) == [true, true, false], "the third run never reached the finish")
        #expect(abs(try #require(runs[0].duration) - 52) < 0.3)
        #expect(abs(try #require(runs[1].duration) - 65) < 0.3)
        // The best is a run, and the driving between runs has no delta to it.
        #expect(SessionStats(session: session).bestLap?.number == 1)
        let between = try #require(session.laps.first { $0.kind == .transit && $0.number == -2 })
        let deltaTimes = try #require(session[.lapDelta]).times
        #expect(!deltaTimes.contains { $0 > between.start && $0 < (between.end ?? 0) })
        #expect(CoachingReference.fastestRolling.resolve(in: session) == nil, "no rolling lap on an open course")
    }

    @Test func withoutAFinishLineItIsTimedInLapsAsBefore() throws {
        let session = try ProjectCompiler.importData(at: Self.vbo, settings: try Self.settings(runs: false))
        #expect(!session.laps.areRuns)
        #expect(session.laps.allSatisfy { $0.kind == .lap })
    }

    @Test func aProjectSavedBeforeRunsHasNoFinishLine() throws {
        let json =
            Data(#"{"lapLine":{"latitude":1,"longitude":2,"halfWidthMeters":25,"#.utf8)
            + Data(#""headingToleranceDegrees":60,"ignoreFirstCrossings":0}}"#.utf8)
        let settings = try JSONDecoder().decode(DataInputSettings.self, from: json)
        #expect(settings.lapLine != nil)
        #expect(settings.runFinishLine == nil)
        #expect(!settings.timesRuns)
        let again = try JSONDecoder().decode(DataInputSettings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)
    }
}
