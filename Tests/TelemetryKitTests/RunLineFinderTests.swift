import Foundation
import Testing

@testable import TelemetryKit

/// Suggested lines for a point-to-point course (#552), from the driving alone.
@Suite struct RunLineFinderTests {
    /// Metres east and north of the scripted origin.
    static func position(of line: FinishLine) -> (x: Double, y: Double) {
        (
            (line.longitude - ScriptedDrive.origin.longitude) * ScriptedDrive.metersPerDegreeEast,
            (line.latitude - ScriptedDrive.origin.latitude) * 110_540
        )
    }

    @Test func anAutocrossGetsItsStartWhereRunsSetOffAndItsFinishWhereTheyEnded() throws {
        let suggestion = try #require(RunLineFinder.suggest(in: RunDetectorTests.autocross()))
        let start = Self.position(of: suggestion.start)
        let finish = Self.position(of: suggestion.finish)
        // Staged at (-10, 0); the finish at (100, 100), and the runs ran on to (50, 100) at speed.
        #expect(abs(start.x - -8) < 3 && abs(start.y) < 3, "start at \(start)")
        #expect(finish.x > 45 && finish.x < 110 && abs(finish.y - 100) < 3, "finish at \(finish)")
        #expect(suggestion.runs == 3 && suggestion.finished == 2, "the off-course run ended elsewhere")
        #expect(suggestion.summary.contains("3 runs set off"))
        let runs = RunDetector.detect(
            in: RunDetectorTests.autocross(), start: suggestion.start, finish: suggestion.finish
        ).listed
        // The suggested lines are a few metres off the real ones: the times are close, not exact.
        #expect(abs(try #require(runs[0].duration) - 52) < 4)
    }

    @Test func aHillClimbsDriveDownIsNotALaunch() throws {
        let up: [ScriptedDrive.Step] = [.drive(toX: 0, y: 1000, speed: 30), .stop(seconds: 30)]
        // Down at a crawl, as the paddock road is driven.
        let down: [ScriptedDrive.Step] = [.drive(toX: 0, y: -10, speed: 6), .stop(seconds: 60)]
        let session = ScriptedDrive.session(from: (0, -10), [.stop(seconds: 5)] + up + down + up)
        let suggestion = try #require(RunLineFinder.suggest(in: session))
        #expect(suggestion.runs == 2 && suggestion.finished == 2)
        #expect(Self.position(of: suggestion.finish).y > 900)
    }

    @Test func oneRunIsEnough() throws {
        let session = ScriptedDrive.session(
            from: (0, -10), [.stop(seconds: 5), .drive(toX: 0, y: 600, speed: 25), .stop(seconds: 10)])
        let suggestion = try #require(RunLineFinder.suggest(in: session))
        #expect(suggestion.runs == 1 && suggestion.finished == 1)
        #expect(suggestion.summary.contains("it ended"))
    }

    @Test func aCircuitWithNoStandingStartHasNoSuggestion() {
        // Rolling laps, never standing still.
        #expect(RunLineFinder.suggest(in: SyntheticTrack.session()) == nil)
    }
}
