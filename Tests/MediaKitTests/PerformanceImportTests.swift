import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #553 from a file: a straight-line log is measured as soon as it is read, into a project or the
/// logbook, and a circuit's laps are not measured until the driver asks. `performance.d/drag.vbo`
/// is two launches at constant accelerations (Scripts/make-performance-fixture.py), so every
/// answer is arithmetic.
@Suite("Performance runs from a file (#553)")
struct PerformanceImportTests {
    static let drag = TrackDayImportTests.fixtures.appending(path: "performance.d/drag.vbo")
    static let circuit = TrackDayImportTests.fixtures.appending(path: "racechrono-v3.csv")

    @Test func aStraightLineLogIsMeasuredOnItsOwn() throws {
        let session = try ProjectCompiler.importData(at: Self.drag, settings: DataInputSettings())
        let performance = try #require(session.performance)
        #expect(performance.attempts.count == 2)
        let launch = try #require(performance.best(.zeroToSixtyMph))
        #expect(launch.attempt == 1)
        #expect(abs(launch.seconds - 26.8224 / 5) < 0.002)
        let quarter = try #require(performance.best(.quarterMile))
        // With the 1-ft rollout: √(2(¼ mile + 1 ft) / a) − √(2 · 1 ft / a).
        let rollout = 0.3048
        let timeslip = (2 * (1320 * 0.3048 + rollout) / 5).squareRoot() - (2 * rollout / 5).squareRoot()
        #expect(abs(quarter.seconds - timeslip) < 0.002)
        let stop = try #require(performance.best(.sixtyMph))
        #expect(abs(stop.stop.metres - 26.8224 * 26.8224 / 20) < 0.05)
        #expect(performance.attempts.allSatisfy { $0.notes.isEmpty }, "level and 10 Hz: nothing to note")
    }

    @Test func aCircuitIsNotMeasuredUntilAsked() throws {
        let laps = try ProjectCompiler.importData(at: Self.circuit, settings: DataInputSettings())
        #expect(!laps.laps.listed.isEmpty)
        #expect(laps.performance == nil, "a pit exit is not measured unasked")
        var settings = DataInputSettings()
        settings.measuresPerformance = true
        #expect(try ProjectCompiler.importData(at: Self.circuit, settings: settings).performance != nil)
        settings.measuresPerformance = false
        #expect(try ProjectCompiler.importData(at: Self.drag, settings: settings).performance == nil)
    }

    @Test func aWholeFolderImportLeavesTheFixtureOut() {
        let files = TrackDayImport.files(in: [TrackDayImportTests.fixtures])
        #expect(!files.contains { $0.lastPathComponent == "drag.vbo" })
    }

    @Test func theLogbookKeepsTheNumbersAndReadsThemBack() async throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "performance-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        _ = await TrackDayImport.run([Self.drag], into: logbook)
        let entry = try #require(logbook.entries().first)
        #expect(entry.measuresPerformance == nil)
        #expect(entry.measuresPerformanceInForce)
        let performance = try #require(entry.performance)
        #expect(performance.attempts.count == 2)
        #expect(abs(try #require(performance.best(.zeroToSixtyMph)).seconds - 26.8224 / 5) < 0.002)

        // Turned off, a reading measures nothing; the file read again measures what it did.
        var off = entry
        off.measuresPerformance = false
        let unmeasured = try #require(LogbookReferences.load(off))
        off.readPerformance(of: unmeasured)
        #expect(off.performance == nil)
        let again = try #require(LogbookReferences.load(entry))
        #expect(again.performance == performance)
    }
}
