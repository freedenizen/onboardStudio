import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

@Suite("Watching a corner (#516)")
struct CornerFootageTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    static func analysis() throws -> CoachingAnalysis {
        let session = try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
        return try #require(CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
    }

    @Test func thisLapsCornerThenTheReferencesFromBeforeBrakingToAfterTheExit() throws {
        let analysis = try Self.analysis()
        let corner = try #require(analysis.top.first?.corner)
        let pieces = CornerFootage.pieces(of: corner, in: analysis, referenceIsFootage: true)
        #expect(pieces.map(\.side) == [.lap, .reference])
        let lap = pieces[0].sessionTimes
        let braking = analysis.lap.time(atDistance: corner.lap.phaseStart)
        let exit = analysis.lap.time(atDistance: corner.lap.phaseEnd)
        #expect(abs(lap.lowerBound - (braking - CornerFootage.leadIn)) < 1e-9)
        #expect(abs(lap.upperBound - (exit + CornerFootage.leadOut)) < 1e-9)
        // The reference is on its own lap: the best lap was driven at another time of the session.
        let reference = pieces[1].sessionTimes
        let referenceBraking = analysis.reference.time(atDistance: corner.reference.phaseStart)
        #expect(abs(reference.lowerBound - (referenceBraking - CornerFootage.leadIn)) < 1e-9)
        #expect(!reference.overlaps(lap))
    }

    @Test func aReferenceWithNoPictureIsLeftOut() throws {
        let analysis = try Self.analysis()
        let corner = try #require(analysis.top.first?.corner)
        #expect(CornerFootage.pieces(of: corner, in: analysis, referenceIsFootage: false).map(\.side) == [.lap])
    }

    @Test func aProjectPlaysItWhereTheSyncAndTheRetimesPutIt() {
        // Data starting 12 s into the log, placed 3 s into the project: session second 40 is
        // project second 31, and with nothing retimed, output second 31.
        let sync = SyncSettings(startPositionInInput: 12, offsetInProject: 3, playSpeed: 1)
        let map = TimeMap.identity(120)
        let range = CornerFootage.outputRange(of: 40...46, sync: sync, timeMap: map)
        #expect(range == 31...37)
        // A picture that ends mid-corner shows what it has; one that ends before shows nothing.
        #expect(CornerFootage.outputRange(of: 40...46, sync: sync, timeMap: .identity(34)) == 31...34)
        #expect(CornerFootage.outputRange(of: 40...46, sync: sync, timeMap: .identity(30)) == nil)
        #expect(CornerFootage.outputRange(of: 10...16, sync: sync, timeMap: map) == 1...7)
        // Before the project starts is cut off too: session 5–11 would be project −4 to 2.
        #expect(CornerFootage.outputRange(of: 5...11, sync: sync, timeMap: map) == 0...2)
    }

    @Test func theDaysClipThatWasRecordingHoldsIt() {
        // The session's clock: session second t is 1_000 + t on the wall clock.
        let epoch: (Double) -> Double? = { 1_000 + $0 }
        let recordings = [
            CornerFootage.Recording(startEpoch: 900, duration: 120),  // 900–1020
            CornerFootage.Recording(startEpoch: 1_030, duration: 600),  // 1030–1630
        ]
        let found = CornerFootage.recordingRange(of: 100...106, epoch: epoch, recordings: recordings)
        #expect(found?.recording == 1)
        #expect(found?.range == 70...76)
        // In the gap between recordings, then the next starts: shown from where that one begins.
        let gap = CornerFootage.recordingRange(of: 25...35, epoch: epoch, recordings: recordings)
        #expect(gap?.recording == 1)
        #expect(gap?.range == 0...5)
        // No recording at the time, or no clock on the session: nothing to watch.
        #expect(CornerFootage.recordingRange(of: 700...706, epoch: epoch, recordings: recordings) == nil)
        #expect(CornerFootage.recordingRange(of: 100...106, epoch: { _ in nil }, recordings: recordings) == nil)
    }
}
