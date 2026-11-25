import Foundation
import Testing

@testable import ProjectModel
@testable import TelemetryKit

/// #553 in the logbook and the project: which sessions are measured, the numbers kept with an
/// entry, and files written before performance runs existed.
@Suite("Performance runs in the logbook and the project (#553)")
struct PerformanceEntryTests {
    static func entry(laps: [LogbookEntry.LapRecord] = []) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/days/drag.vbo", contentHash: "drag", byteCount: 1, importerID: "vbo"), laps: laps)
    }

    /// Standing for 2 s, then 5 m/s² for 20 s, at 10 Hz.
    static var launch: TelemetrySession {
        let times = (0...220).map { Double($0) / 10 }
        let speeds = times.map { max(0, $0 - 2) * 5 }
        let distances = times.map { pow(max(0, $0 - 2), 2) * 2.5 }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(role: .speed, name: "v", unit: .metersPerSecond, times: times, values: speeds),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances),
            ])
    }

    @Test func aSessionWithNoLapsIsMeasuredWithItsReading() throws {
        var entry = Self.entry()
        #expect(entry.measuresPerformanceInForce)
        entry.readLaps(of: Self.launch)
        let launch = try #require(entry.performance?.best(.zeroToSixtyMph))
        #expect(abs(launch.seconds - 26.8224 / 5) < 1e-6)
    }

    /// #677: a clip of the paddock arrived measured, its pit-lane launches under the car's bests.
    @Test func aCamerasRecordingIsMeasuredOnlyWhenAsked() {
        var clip = LogbookEntry(
            file: .init(path: "/days/GX010001.MP4", contentHash: "clip", byteCount: 1, importerID: "gopro"))
        #expect(clip.isCameraRecording && !Self.entry().isCameraRecording)
        #expect(!clip.measuresPerformanceInForce, "no laps, but not a logger's file")
        clip.readPerformance(of: Self.launch)
        #expect(clip.performance == nil, "nothing is measured unasked")
        clip.measuresPerformance = true
        clip.readPerformance(of: Self.launch)
        #expect(clip.performance?.attempts.count == 1, "asked, it is measured like any session")
        clip.measuresPerformance = false
        #expect(!clip.measuresPerformanceInForce)
    }

    /// The recordings measured before the rule changed keep their numbers and stay measured.
    @Test func aRecordingAlreadyMeasuredStaysMeasured() throws {
        var before = LogbookEntry(
            file: .init(path: "/days/GX010002.mp4", contentHash: "old", byteCount: 1, importerID: "gopro"))
        before.performance = PerformanceRuns.measure(in: Self.launch)
        let read = try JSONDecoder().decode(LogbookEntry.self, from: try JSONEncoder().encode(before))
        #expect(read.measuresPerformance == nil, "nothing was asked: it was the rule then")
        #expect(read.measuresPerformanceInForce)
        var again = read
        again.readPerformance(of: Self.launch)
        #expect(again.performance == before.performance, "read again, it is measured again")
    }

    @Test func aSessionWithLapsIsMeasuredOnlyWhenAsked() {
        var entry = Self.entry(laps: [.init(number: 1, seconds: 90, isComplete: true)])
        #expect(!entry.measuresPerformanceInForce)
        entry.readPerformance(of: Self.launch)
        #expect(entry.performance == nil, "a pit exit is not measured unasked")
        entry.measuresPerformance = true
        entry.readPerformance(of: Self.launch)
        #expect(entry.performance?.attempts.count == 1)
        #expect(entry.readingSettings.measuresPerformance == true, "read again, the file is measured too")
    }

    @Test func whatTheReadingMeasuredIsTakenAsItIs() {
        var session = Self.launch
        session.performance = PerformanceRuns.Result()
        var entry = Self.entry()
        entry.readPerformance(of: session)
        #expect(entry.performance == PerformanceRuns.Result(), "not measured twice")
    }

    @Test func theNumbersAreKeptWithTheEntry() throws {
        var entry = Self.entry()
        entry.measuresPerformance = true
        entry.readPerformance(of: Self.launch)
        let read = try JSONDecoder().decode(LogbookEntry.self, from: try JSONEncoder().encode(entry))
        #expect(read.measuresPerformance == true)
        #expect(read.performance == entry.performance)
    }

    @Test func anEntryWrittenBeforeIsAutomaticWithNothingMeasured() throws {
        var root = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(Self.entry())) as? [String: Any])
        root["measuresPerformance"] = nil
        root["performance"] = nil
        let old = try JSONDecoder().decode(LogbookEntry.self, from: try JSONSerialization.data(withJSONObject: root))
        #expect(old.measuresPerformance == nil)
        #expect(old.performance == nil)
    }

    @Test func aProjectSavedBeforeIsAutomatic() throws {
        let settings = try JSONDecoder().decode(DataInputSettings.self, from: Data("{}".utf8))
        #expect(settings.measuresPerformance == nil)
        var asked = settings
        asked.measuresPerformance = false
        let read = try JSONDecoder().decode(DataInputSettings.self, from: try JSONEncoder().encode(asked))
        #expect(read.measuresPerformance == false)
    }

    @Test func theWordingFollowsTheSpeedUnit() {
        #expect(PerformanceWording.launch(metric: false).label == "0–60 mph")
        #expect(PerformanceWording.launch(metric: true).label == "0–100 km/h")
        #expect(PerformanceWording.braking(metric: true).label == "100–0 km/h")
        #expect(
            PerformanceWording.speedRanges(metric: false).map(\.label) == [
                "0–30 mph", "0–60 mph", "0–100 mph", "60–130 mph",
            ])
        #expect(PerformanceWording.mark(12.3417, trap: 62.6, metric: false) == "12.34 s @ 140 mph")
        #expect(PerformanceWording.mark(5, trap: nil, metric: true) == "5.00 s")
        #expect(PerformanceWording.distance(35.97, metric: false) == "118 ft")
        #expect(PerformanceWording.distance(35.97, metric: true) == "36.0 m")
    }
}
