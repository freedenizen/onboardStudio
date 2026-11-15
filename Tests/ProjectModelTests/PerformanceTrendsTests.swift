import Foundation
import Testing

@testable import ProjectModel
@testable import TelemetryKit

/// #553 step 3: the measured sessions across the logbook, and each car's personal bests.
@Suite("Performance runs across sessions (#553)")
struct PerformanceTrendsTests {
    static let day: TimeInterval = 86_400

    /// A session in `car` on day `day` with one launch reaching 0–60 mph in `launch` seconds (and
    /// 0–100 km/h a little later), a quarter mile in `quarter`, and a 60–0 of `stop` metres.
    static func entry(
        _ car: String, day: Double, launch: Double? = nil, quarter: Double? = nil, stop: Double? = nil
    ) -> LogbookEntry {
        var entry = LogbookEntry(
            file: .init(path: "/days/\(car)-\(day).vbo", contentHash: "\(car)\(day)", byteCount: 1, importerID: "vbo"),
            date: Date(timeIntervalSince1970: day * Self.day), car: car)
        var attempt = PerformanceRuns.Attempt(start: 0, end: 20, sampleHertz: 10)
        if let launch {
            attempt.speedTimes[.zeroToSixtyMph] = launch
            attempt.speedTimes[.zeroToHundredKmh] = launch + 0.2
        }
        if let quarter {
            attempt.distanceTimes[.quarterMile] = quarter
            attempt.trapSpeeds[.quarterMile] = 50
        }
        var result = PerformanceRuns.Result()
        if launch != nil || quarter != nil { result.attempts = [attempt] }
        if let stop { result.stops = [PerformanceRuns.Stop(from: .sixtyMph, start: 30, end: 33, metres: stop)] }
        entry.performance = result
        return entry
    }

    @Test func eachMeasuredSessionIsAPointInDateOrder() {
        let entries = [
            Self.entry("Miata", day: 3, launch: 6.1),
            Self.entry("Miata", day: 1, launch: 6.5, quarter: 14.9, stop: 40),
            LogbookEntry(file: .init(path: "/days/lap.csv", contentHash: "lap", byteCount: 1, importerID: "rc")),
        ]
        let points = PerformanceTrends.points(for: entries, metric: false)
        #expect(points.map(\.launch) == [6.5, 6.1], "oldest first; a session with nothing measured is left out")
        #expect(points[0].quarterMile == 14.9)
        #expect(points[0].trap == 50)
        #expect(points[0].stop == 40)
        #expect(PerformanceTrends.points(for: entries, metric: true).map(\.launch) == [6.7, 6.3], "0–100 km/h")
        #expect(PerformanceTrends.points(for: entries, metric: true)[0].stop == nil, "no stop from 100 km/h")
    }

    @Test func aCarIsOneCarHoweverItsNameIsTyped() {
        let entries = [Self.entry("Miata", day: 1, launch: 6.5), Self.entry(" miata", day: 2, launch: 6.2)]
        #expect(PerformanceTrends.points(for: entries, car: "MIATA", metric: false).count == 2)
        let bests = PerformanceTrends.bests(in: PerformanceTrends.points(for: entries, metric: false))
        #expect(bests.count == 1)
        #expect(bests.first?.launch?.value == 6.2)
    }

    @Test func personalBestsAreKeptPerCarNotPerSession() throws {
        let entries = [
            Self.entry("Miata", day: 1, launch: 6.5, quarter: 14.9, stop: 38),
            Self.entry("GR86", day: 2, launch: 6.0, stop: 36),
            Self.entry("Miata", day: 3, launch: 6.2, quarter: 15.1, stop: 39),
            Self.entry("", day: 4, launch: 7.0),
        ]
        let points = PerformanceTrends.points(for: entries, metric: false)
        let bests = PerformanceTrends.bests(in: points)
        #expect(bests.map(\.car) == ["GR86", "Miata", ""], "cars by name, no car last")
        let miata = try #require(bests.first { $0.car == "Miata" })
        #expect(miata.launch?.value == 6.2)
        #expect(miata.launch?.entryID == entries[2].id)
        #expect(miata.quarterMile?.value == 14.9)
        #expect(miata.quarterMile?.trap == 50)
        #expect(miata.quarterMile?.entryID == entries[0].id)
        #expect(miata.stop?.value == 38)
        #expect(bests[0].quarterMile == nil, "the GR86 never ran a quarter")
    }

    @Test func aTieDoesNotTakeTheBest() {
        let entries = [Self.entry("Miata", day: 1, launch: 6.2), Self.entry("Miata", day: 2, launch: 6.2)]
        let bests = PerformanceTrends.bests(in: PerformanceTrends.points(for: entries, metric: false))
        #expect(bests.first?.launch?.entryID == entries[0].id)
    }

    @Test func theSummarySaysWhereEachCarsLaunchWent() {
        let entries = [
            Self.entry("Miata", day: 1, launch: 6.5), Self.entry("Miata", day: 3, launch: 6.2),
            Self.entry("GR86", day: 2, launch: 6.0),
        ]
        let points = PerformanceTrends.points(for: entries, metric: false)
        #expect(
            PerformanceTrends.summary(of: points, metric: false)
                == "In the GR86, one 0–60 mph so far: 6.00 s. "
                + "In the Miata, 0–60 mph 6.50 s in the first session, best 6.20 s: quicker by 0.30 s.")
        #expect(PerformanceTrends.summary(of: [], metric: true) == "No 0–100 km/h measured yet.")
    }

    @Test func theChartLayoutGroupsADaysSessions() {
        let start = Date(timeIntervalSince1970: 10 * Self.day + 3_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let layout = TrendsChartLayout(
            dates: [start, start + 600, start + 2 * Self.day], calendar: calendar)
        #expect(layout.positions == [0, 1, 3])
        #expect(layout.days.count == 2)
    }
}
