import Foundation
import Testing

@testable import TelemetryKit

@Suite("Coaching report")
struct CoachingReportTests {
    @Test func theReportEncodesTheWordsAndNumbersButNoSamples() throws {
        let session = CoachingAnalysisTests.session
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(CoachingReport(analysis))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["referencePhrase"] as? String == "your best lap")
        #expect((object["opportunities"] as? [[String: Any]])?.count == 2)
        #expect((object["corners"] as? [[String: Any]])?.count == 2)
        let lap = try #require(object["lap"] as? [String: Any])
        #expect(lap["label"] as? String == "Lap 2")
        #expect((lap["sources"] as? [String: String])?["speed"] == "speedTrace")
        let first = try #require((object["opportunities"] as? [[String: Any]])?.first)
        let note = try #require(first["note"] as? [String: Any])
        #expect((note["headline"] as? String)?.hasPrefix("Turn ") == true)
        // The profiles' samples are not in the report: a few kilobytes, not megabytes.
        #expect(data.count < 20_000, "\(data.count) bytes")
        #expect(object["delta"] == nil)
    }
}
