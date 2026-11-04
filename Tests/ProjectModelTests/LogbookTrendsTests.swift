import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

@Suite("Logbook trends (#353)")
struct LogbookTrendsTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    func visit(
        _ hash: String, day: Double, best: Double?, laps: [Double?] = [], corners: [CornerRecord] = [], car: String = ""
    ) -> LogbookEntry {
        let records = laps.enumerated().map {
            LogbookEntry.LapRecord(number: $0.offset + 1, seconds: $0.element, isComplete: $0.element != nil)
        }
        return LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"), trackName: "Stadium",
            date: Date(timeIntervalSince1970: 1_700_000_000 + day * 86_400), car: car, laps: records,
            bestLap: best, bestLapNumber: best == nil ? nil : 1, corners: corners)
    }

    func corner(_ label: String, brake: Double?, minimum: Double, time: Double) -> CornerRecord {
        CornerRecord(
            index: 0, label: label, brakePointMeters: brake, minimumSpeed: minimum, exitSpeed: 30, timeInCorner: time)
    }

    @Test func pointsAreTheDatedVisitsOldestFirstWithTheirSpread() {
        let entries = [
            visit("b", day: 30, best: 116.9, laps: [116.9, 117.4, 117.9, 130.0], car: "Miata"),
            visit("a", day: 0, best: 118.0, laps: [118.0, 118.2], car: "Miata"),
            visit("c", day: 60, best: 112.4, car: "GR86"),
            LogbookEntry(
                file: .init(path: "/d/o.csv", contentHash: "o", byteCount: 1, importerID: "x"), trackName: "Other",
                date: Date(), bestLap: 90),
        ]
        let points = LogbookTrends.points(for: entries, circuitKey: "Stadium")
        #expect(points.map(\.best) == [118.0, 116.9, 112.4])
        #expect(points[0].spread == nil, "two laps say nothing about consistency")
        let spread = try? #require(points[1].spread)
        #expect((spread ?? 0) > 0.4 && (spread ?? 0) < 0.6, "the 130 s lap is not a flying lap: \(spread ?? -1)")
        #expect(LogbookTrends.points(for: entries, circuitKey: "Stadium", car: "miata").count == 2)
        #expect(LogbookTrends.summary(of: points).hasPrefix("Best lap 1:58.00 in"))
        #expect(LogbookTrends.summary(of: points).contains("quicker by 5.60 s over 3 visits"))
        #expect(LogbookTrends.summary(of: []) == "No complete laps to compare yet.")
    }

    @Test func cornersAreComparedWithTheLastVisitAndThePersonalBest() {
        let entries = [
            visit(
                "pb", day: 0, best: 110,
                corners: [
                    corner("1", brake: 120, minimum: 20, time: 8.0), corner("2", brake: 90, minimum: 15, time: 6.0),
                ]),
            visit("prev", day: 10, best: 114, corners: [corner("1", brake: 130, minimum: 18, time: 8.6)]),
            visit(
                "latest", day: 20, best: 112,
                corners: [
                    corner("1", brake: 124, minimum: 19, time: 8.2), corner("2", brake: nil, minimum: 14, time: 6.3),
                ]),
        ]
        let trends = LogbookTrends.cornerTrends(for: entries, circuitKey: "Stadium")
        #expect(trends.map(\.label) == ["1", "2"])
        let one = trends[0]
        #expect(one.brakePointChange == -6 && one.brakePointToBest == 4)
        #expect(one.minimumSpeedChange == 1 && one.minimumSpeedToBest == -1)
        #expect((one.timeChange ?? 0).isApproximately(-0.4) && (one.timeToBest ?? 0).isApproximately(0.2))
        let two = trends[1]
        #expect(two.previous == nil && two.brakePointToBest == nil, "no previous reading, no brake point this time")
        #expect((two.timeToBest ?? 0).isApproximately(0.3))
        // The latest visit being the personal best, there is nothing to compare it with as PB.
        let own = LogbookTrends.cornerTrends(for: Array(entries.prefix(1)), circuitKey: "Stadium")
        #expect(own.first?.best == nil)
    }

    @Test func anEntryKeepsTheCornersOfItsBestLap() throws {
        let session = try RaceRenderCSVImporter().importSession(at: Self.fixture, options: SessionBuilder.Options())
        let entry = try LogbookEntry.make(
            session: session, file: Self.fixture, importerID: "racerender-csv", circuitID: nil)
        #expect(entry.corners.map(\.label) == ["1", "2"])
        #expect(entry.corners.allSatisfy { $0.brakePointMeters != nil && $0.minimumSpeed > 10 && $0.timeInCorner > 1 })
        let back = try Logbook.decoder.decode(LogbookEntry.self, from: try Logbook.encoder.encode(entry))
        #expect(back.corners == entry.corners)
    }
}

extension Double {
    fileprivate func isApproximately(_ other: Double) -> Bool { abs(self - other) < 0.001 }
}
