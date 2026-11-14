import Foundation
import Testing

@testable import ProjectModel

/// Sessions in runs on courses (#552): the same course when the lines and the path agree, a new
/// one when a layout moved, and a course's sessions kept apart from the venue's others.
@Suite struct RunCourseTests {
    static let origin = (latitude: 47.0, longitude: 8.0)
    static let eastPerDegree = 111_320 * cos(origin.latitude * .pi / 180)

    static func point(_ x: Double, _ y: Double) -> CoursePoint {
        CoursePoint(latitude: origin.latitude + y / 110_540, longitude: origin.longitude + x / eastPerDegree)
    }

    static func line(_ x: Double, _ y: Double) -> LapLineSpec {
        let p = point(x, y)
        return LapLineSpec(latitude: p.latitude, longitude: p.longitude)
    }

    /// Out east 200 m, then north 100 m to the finish; `bend` moves the corner.
    static func path(bend: Double = 200) -> [CoursePoint] {
        stride(from: 0.0, through: bend, by: 4).map { point($0, 0) }
            + stride(from: 4.0, through: 100, by: 4).map { point(bend, $0) }
    }

    static func entry(
        lines: RunLines?, path: [CoursePoint], course: CourseTag? = nil, track: String = "Lot 4"
    ) -> LogbookEntry {
        var entry = LogbookEntry(
            file: .init(
                path: "/tmp/\(UUID().uuidString).vbo", contentHash: UUID().uuidString, byteCount: 1,
                importerID: "vbo"),
            trackName: track, date: Date(timeIntervalSince1970: 1_800_000_000), bestLap: 50)
        entry.runLines = lines
        entry.coursePath = path
        entry.course = course
        return entry
    }

    static let lines = RunLines(start: line(0, 0), finish: line(200, 100))

    @Test func theSameLinesAndPathAreTheSameCourse() {
        let tag = CourseTag(name: "Course of 12 Oct")
        let earlier = Self.entry(lines: Self.lines, path: Self.path(), course: tag)
        // Lines placed a few metres from last time, and a path a metre or two off.
        let nudged = RunLines(start: Self.line(4, 2), finish: Self.line(203, 98))
        let path = Self.path().map { CoursePoint(latitude: $0.latitude + 1.5 / 110_540, longitude: $0.longitude) }
        #expect(RunCourse.course(lines: nudged, path: path, date: nil, among: [earlier]) == tag)
    }

    @Test func aMovedLayoutIsANewCourse() {
        let tag = CourseTag(name: "Course of 12 Oct")
        let earlier = Self.entry(lines: Self.lines, path: Self.path(), course: tag)
        // Same start and finish, but the corner 40 m earlier: a different layout.
        let moved = RunLines(start: Self.line(0, 0), finish: Self.line(160, 100))
        let other = RunCourse.course(lines: moved, path: Self.path(bend: 160), date: nil, among: [earlier])
        #expect(other.id != tag.id)
        #expect(other.name == "New course")
        // The same lines but a path through other cones is a new course too.
        let wiggle = Self.path().map { CoursePoint(latitude: $0.latitude + 12 / 110_540, longitude: $0.longitude) }
        #expect(RunCourse.course(lines: Self.lines, path: wiggle, date: nil, among: [earlier]).id != tag.id)
    }

    @Test func aCoursesSessionsAreKeptApartFromTheVenuesOthers() {
        let tag = CourseTag(name: "Course of 12 Oct")
        let run = Self.entry(lines: Self.lines, path: Self.path(), course: tag)
        let laps = Self.entry(lines: nil, path: [])
        #expect(LogbookFilter.circuitKey(of: run) == RunCourse.key(tag.id))
        #expect(LogbookFilter.venueKey(of: run) == "Lot 4")
        #expect(LogbookFilter.circuitKey(of: laps) == "Lot 4")
        #expect(run.title == "Lot 4 – Course of 12 Oct")
        #expect(Self.entry(lines: Self.lines, path: [], course: tag, track: "").title == "Course of 12 Oct")
        #expect(PersonalBests.best(in: [run, laps], circuitKey: "Lot 4")?.entryID == laps.id)
    }

    @Test func readingSettingsTimeTheFileInRuns() {
        let run = Self.entry(lines: Self.lines, path: Self.path())
        #expect(run.readingSettings.timesRuns)
        #expect(run.readingSettings.importerID == "vbo")
        #expect(!Self.entry(lines: nil, path: []).readingSettings.timesRuns)
    }

    @Test func anEntryWrittenBeforeRunsIsLaps() throws {
        let entry = Self.entry(lines: nil, path: [])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any] ?? [:]
        json["runLines"] = nil
        json["course"] = nil
        json["coursePath"] = nil
        let decoded = try JSONDecoder().decode(LogbookEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!decoded.isRuns)
        #expect(decoded.course == nil)
        #expect(decoded.coursePath.isEmpty)
    }
}
