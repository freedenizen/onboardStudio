import Foundation
import TelemetryKit

extension LapLineSpec {
    /// A gate as the detectors want it: the middle of the line, and how far it reaches either
    /// side. The heading is left unset — a gate says where the line is and not which way the car
    /// crosses it, and the two perpendiculars are equally consistent with it.
    public init(gate: LapGate) {
        self.init(latitude: gate.centreLatitude, longitude: gate.centreLongitude, halfWidthMeters: gate.halfWidthMeters)
    }
}

/// The start and the finish of a point-to-point course (#552): how a session's file is timed in
/// runs, kept on its logbook entry so the file reads the same way every time it is read again.
public struct RunLines: Hashable, Codable, Sendable {
    public var start: LapLineSpec
    public var finish: LapLineSpec

    public init(start: LapLineSpec, finish: LapLineSpec) {
        self.start = start
        self.finish = finish
    }

    /// The lines a file recorded, when it carries both a start and a finish gate.
    public init?(_ geometry: LapGeometry) {
        guard let start = geometry.start, let finish = geometry.finish else { return nil }
        self.init(start: LapLineSpec(gate: start), finish: LapLineSpec(gate: finish))
    }

    /// A data input's lines, when it is timed in runs.
    public init?(_ settings: DataInputSettings) {
        guard let start = settings.lapLine, let finish = settings.runFinishLine else { return nil }
        self.init(start: start, finish: finish)
    }
}

/// Which course a session in runs was driven on, and what the driver calls it.
///
/// A course is the same course when the geometry says so (`RunCourse.matches`): a hill climb is
/// one course visit after visit, and an autocross car park a new one each time its cones move.
/// The id and name are kept on every session of the course rather than in a list of their own,
/// so renaming one, or saying two are the same, is an ordinary logbook edit and undoes as one.
public struct CourseTag: Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// A point of a course's path.
public struct CoursePoint: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// How sessions in runs are put on courses.
public enum RunCourse {
    /// Lines further apart than this are not the same course's (m). A line placed by hand on two
    /// days lands a few metres apart; a gate moved to a different part of a car park does not.
    public static let lineTolerance = 15.0
    /// Paths further apart than this on average are different layouts (m): a single gate moved
    /// moves the line through that part of the course by more, and GPS repeats to a metre or two.
    public static let pathTolerance = 5.0
    /// The path is kept every this many metres.
    public static let pathStep = 4.0

    /// The key a course's personal bests, Trends and goals are kept under, where a circuit's are
    /// kept under its id or name.
    public static func key(_ id: UUID) -> String { "course:" + id.uuidString }

    /// "Course of 12 Oct 2026", or "New course" without a date.
    public static func defaultName(for date: Date?) -> String {
        date.map { "Course of " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "New course"
    }

    /// The path of `session`'s quickest finished run, every `pathStep` metres; empty without one.
    public static func path(of session: TelemetrySession) -> [CoursePoint] {
        guard let run = LapDeltas.sessionBest(in: session), let end = run.end,
            let distance = session[.distance], let lat = session[.latitude], let lon = session[.longitude],
            let from = distance.value(at: run.start), let to = distance.value(at: end), to > from
        else { return [] }
        var points: [CoursePoint] = []
        var index = distance.times.firstIndex { $0 >= run.start } ?? distance.count
        var next = from
        while index < distance.count, distance.times[index] <= end {
            if distance.values[index] >= next {
                let time = distance.times[index]
                if let latitude = lat.value(at: time), let longitude = lon.value(at: time) {
                    points.append(CoursePoint(latitude: latitude, longitude: longitude))
                }
                next = distance.values[index] + pathStep
            }
            index += 1
        }
        return points
    }

    /// Whether a session timed by `lines` along `path` was driven on the course whose session is
    /// `other`: both lines within `lineTolerance` of its, and the paths within `pathTolerance` of
    /// each other on average, measured both ways so a short cut is not hidden inside a longer path.
    public static func matches(lines: RunLines, path: [CoursePoint], _ other: LogbookEntry) -> Bool {
        guard let theirs = other.runLines, !path.isEmpty, !other.coursePath.isEmpty else { return false }
        guard distance(lines.start, theirs.start) <= lineTolerance,
            distance(lines.finish, theirs.finish) <= lineTolerance
        else { return false }
        return meanDistance(from: path, to: other.coursePath) <= pathTolerance
            && meanDistance(from: other.coursePath, to: path) <= pathTolerance
    }

    /// The course of the session that `lines` and `path` describe: the course of the first entry in
    /// `entries` it matches, else a new one named for `date`.
    public static func course(
        lines: RunLines, path: [CoursePoint], date: Date?, among entries: [LogbookEntry]
    ) -> CourseTag {
        for other in entries {
            if let tag = other.course, matches(lines: lines, path: path, other) { return tag }
        }
        return CourseTag(name: defaultName(for: date))
    }

    static func distance(_ a: LapLineSpec, _ b: LapLineSpec) -> Double {
        metres(
            CoursePoint(latitude: a.latitude, longitude: a.longitude),
            CoursePoint(latitude: b.latitude, longitude: b.longitude))
    }

    static func meanDistance(from path: [CoursePoint], to other: [CoursePoint]) -> Double {
        guard !path.isEmpty, !other.isEmpty else { return .infinity }
        let total = path.reduce(0.0) { sum, point in sum + (other.map { metres(point, $0) }.min() ?? .infinity) }
        return total / Double(path.count)
    }

    /// Metres between two points, on a plane: courses are a few hundred metres across.
    static func metres(_ a: CoursePoint, _ b: CoursePoint) -> Double {
        let north = (a.latitude - b.latitude) * 110_540
        let east = (a.longitude - b.longitude) * 111_320 * cos(a.latitude * .pi / 180)
        return (north * north + east * east).squareRoot()
    }
}

extension LogbookEntry {
    /// Its laps read from `session`, which was read between `lines` (or as laps, with none), and,
    /// for runs, the course they were on: the one it is on when the lines have not moved — a
    /// course the driver chose stays chosen — else the course in `entries` it matches, else a new
    /// one.
    public mutating func readRuns(_ lines: RunLines?, of session: TelemetrySession, among entries: [LogbookEntry]) {
        let moved = lines != runLines
        runLines = lines
        readLaps(of: session)
        guard let lines else {
            course = nil
            coursePath = []
            return
        }
        coursePath = RunCourse.path(of: session)
        if moved || course == nil {
            let others = entries.filter { $0.id != id }
            course = RunCourse.course(lines: lines, path: coursePath, date: date, among: others)
        }
    }
}

/// Cones and off-courses (#552): what an autocross run's time counts as.
public enum RunPenalty {
    /// Seconds per cone when the day says nothing: the usual club rule.
    public static let defaultPerCone = 2.0
}

extension LogbookEntry {
    /// Takes the penalty per cone of the day it is on, when it is timed in runs.
    public mutating func takePenalty(from day: TrackDay) {
        guard isRuns, penaltyPerCone != day.penaltyPerCone else { return }
        penaltyPerCone = day.penaltyPerCone
        applyPenalties()
    }

    /// Seconds a cone adds to one of its runs.
    public var perCone: Double { penaltyPerCone ?? RunPenalty.defaultPerCone }

    /// For runs, the best is the quickest **official** time — the clock plus the cones, with DNFs
    /// left out — so the personal best, Trends, goals and the import report compare what counts.
    /// The optimal run stays the driving's own: the best sectors, whatever was hit.
    public mutating func applyPenalties() {
        guard isRuns else { return }
        let official = laps.compactMap { lap in lap.officialSeconds(perCone: perCone).map { (lap.number, $0) } }
        let best = official.min { $0.1 < $1.1 }
        bestLap = best?.1
        bestLapNumber = best?.0
    }
}
