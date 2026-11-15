import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

/// #557: each lap of a logbook session keeps its sector times and its top and minimum speed.
@Suite("Sector splits and speeds per lap (#557)")
struct LapSplitsTests {
    static let fixture = LogbookTests.fixture

    static func session() throws -> TelemetrySession {
        try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
    }

    @Test func eachLapKeepsItsSectorsAndSpeeds() throws {
        let session = try Self.session()
        let entry = try LogbookEntry.make(
            session: session, file: Self.fixture, importerID: "racerender-csv", circuitID: nil)
        #expect(entry.splitsMeasurement == LogbookEntry.splitsMeasurement)
        #expect(!entry.needsSplitReading)
        #expect(entry.sectorCount == 3)
        let analysis = try #require(session.sectors)
        for lap in entry.laps {
            #expect(lap.sectors == analysis.times(ofLap: lap.number), "lap \(lap.number)")
            if lap.isComplete, let seconds = lap.seconds, let total = LapSectors(lapNumber: 0, times: lap.sectors).total
            {
                #expect(abs(total - seconds) < 0.05, "lap \(lap.number)'s sectors add up to its time")
            }
            let sessionLap = try #require(session.laps.first { $0.number == lap.number })
            let end = sessionLap.end ?? .infinity
            let channel = try #require(session[.speed])
            let speeds = zip(channel.times, channel.values).filter { $0.0 >= sessionLap.start && $0.0 <= end }.map(\.1)
            #expect(lap.topSpeed == speeds.max())
            #expect(lap.minSpeed == speeds.min())
        }
        #expect(entry.bestSectors == analysis.bestTimes)
    }

    @Test func theBestsAndTheGapAreTheSessions() {
        var entry = LogbookEntry(
            file: .init(path: "/a.csv", contentHash: "a", byteCount: 1, importerID: "rc"), bestLap: 60, bestLapNumber: 2
        )
        entry.laps = [
            .init(number: 1, seconds: 61.5, isComplete: true, sectors: [20, 21, 20.5], topSpeed: 50, minSpeed: 20),
            .init(number: 2, seconds: 60, isComplete: true, sectors: [20.5, 19.5, 20], topSpeed: 49, minSpeed: 22),
            .init(number: 3, seconds: 30, isComplete: false, sectors: [19, nil, nil], topSpeed: 55, minSpeed: 2),
        ]
        #expect(entry.bestSectors == [19, 19.5, 20], "a partial lap's timed sector counts, as it does in the optimal")
        #expect(entry.gapToBest(entry.laps[0]) == 1.5)
        #expect(entry.gapToBest(entry.laps[1]) == 0)
        #expect(entry.gapToBest(entry.laps[2]) == nil, "an unfinished lap is not off the best")
        #expect(entry.bestTopSpeed == 50, "an unfinished lap's speeds are no record")
        #expect(entry.bestMinSpeed == 22, "the higher minimum is the better")
    }

    @Test func theLapTheRecordingBeganDuringHasNoSectors() {
        // A lap round a 1 km straight at 10 m/s: 100 s a lap, the recording begun 40 s into the first.
        let times = (0...2_600).map { Double($0) / 10 }
        let distance = times.map { $0 * 10 }
        let speed = times.map { 10 + ($0.truncatingRemainder(dividingBy: 100) < 50 ? 1.0 : 0) }
        let laps = [
            Lap(number: 0, start: 0, end: 60, isComplete: false),
            Lap(number: 1, start: 60, end: 160, isComplete: true),
            Lap(number: 2, start: 160, end: 260, isComplete: true),
        ]
        var session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distance),
                Channel(role: .speed, name: "v", unit: .metersPerSecond, times: times, values: speed),
            ],
            laps: laps)
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 2), session: session)
        var entry = LogbookEntry(file: .init(path: "/b.csv", contentHash: "b", byteCount: 1, importerID: "rc"))
        entry.laps = laps.map { .init(number: $0.number, seconds: $0.duration, isComplete: $0.isComplete) }
        #expect(entry.needsSplitReading, "laps without their sectors yet")
        entry.readSplits(of: session)
        #expect(entry.laps[0].sectors == [nil, nil], "its first sector began where the recording did, not at the line")
        #expect(entry.laps[1].sectors.map { $0.map { ($0 * 10).rounded() / 10 } } == [50, 50])
        #expect(entry.laps[0].topSpeed == 11, "its speeds are still its own")
        #expect(entry.laps[1].minSpeed == 10)
        #expect(entry.bestSectors.compactMap { $0 }.count == 2)
    }

    @Test func anEntryFromBeforeTheSplitsReadsWithoutThem() throws {
        let json = """
            {"file": {"path": "/c.csv", "contentHash": "c", "byteCount": 1, "importerID": "rc"},
             "laps": [{"number": 1, "seconds": 61.5, "isComplete": true}]}
            """
        let entry = try JSONDecoder().decode(LogbookEntry.self, from: Data(json.utf8))
        #expect(entry.laps[0].sectors.isEmpty)
        #expect(entry.laps[0].topSpeed == nil)
        #expect(entry.splitsMeasurement == 0)
        #expect(entry.needsSplitReading)

        var read = entry
        read.laps[0].sectors = [20, nil, 21]
        read.laps[0].topSpeed = 50
        read.splitsMeasurement = 1
        let again = try JSONDecoder().decode(LogbookEntry.self, from: JSONEncoder().encode(read))
        #expect(again.laps[0].sectors == [20, nil, 21], "an untimed sector stays untimed")
        #expect(again.laps[0].topSpeed == 50)
        #expect(!again.needsSplitReading)
    }
}
