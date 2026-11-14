import CryptoKit
import Foundation
import TelemetryKit

/// One session in the logbook (#345): which file it is, where and when it was driven, what was
/// driven, and its laps — the numbers without the samples, so a season is small and reads fast.
public struct LogbookEntry: Identifiable, Hashable, Codable, Sendable {
    /// The data file: its path when it was added, a bookmark that follows a move, and a hash of
    /// its bytes so the same file is never entered twice.
    public struct SourceFile: Hashable, Codable, Sendable {
        public var path: String
        public var bookmark: Data?
        /// SHA-256 of the file's bytes, hex.
        public var contentHash: String
        public var byteCount: Int
        public var importerID: String

        public init(path: String, bookmark: Data? = nil, contentHash: String, byteCount: Int, importerID: String) {
            self.path = path
            self.bookmark = bookmark
            self.contentHash = contentHash
            self.byteCount = byteCount
            self.importerID = importerID
        }
    }

    public struct LapRecord: Hashable, Codable, Sendable {
        public var number: Int
        public var seconds: Double?
        public var isComplete: Bool
        /// Cones the run knocked over (#552), each adding the day's penalty to its time.
        public var cones: Int
        /// The driver says the run went off course: a DNF, though it crossed the finish.
        public var offCourse: Bool

        public init(number: Int, seconds: Double?, isComplete: Bool, cones: Int = 0, offCourse: Bool = false) {
            self.number = number
            self.seconds = seconds
            self.isComplete = isComplete
            self.cones = cones
            self.offCourse = offCourse
        }

        /// Never reached the finish, or went off course on the way: a run with no time to count.
        public var isDNF: Bool { !isComplete || offCourse }

        /// The run's time as it counts: what the clock read plus `perCone` for each cone; `nil`
        /// for a DNF.
        public func officialSeconds(perCone: Double) -> Double? {
            guard !isDNF, let seconds else { return nil }
            return seconds + Double(cones) * perCone
        }
    }

    /// A project made from the session, so the entry can lead back to the work.
    public struct ProjectLink: Hashable, Codable, Sendable {
        public var path: String
        public var name: String

        public init(path: String, name: String) {
            self.path = path
            self.name = name
        }
    }

    public var id: UUID
    public var file: SourceFile
    /// Wikidata id of the circuit when recognised; the layout, when the file names one.
    public var circuitID: String?
    public var trackName: String?
    /// When the session was recorded, from the file; `nil` when the file does not say.
    public var date: Date?
    public var car: String
    public var driver: String
    public var laps: [LapRecord]
    public var bestLap: Double?
    public var bestLapNumber: Int?
    public var optimalLap: Double?
    public var fastestRollingLap: Double?
    /// m/s.
    public var topSpeed: Double?
    /// Metres driven in the session, when the file recorded a distance (#355).
    public var distanceMeters: Double?
    public var notes: String
    public var tags: [String]
    /// Weather, track, temperature, tyres and setup (#348); empty until the driver fills it in.
    public var conditions: SessionConditions
    public var projects: [ProjectLink]
    /// The videos exported from projects made from it (#349).
    public var exports: [ProjectLink]
    /// The corners of the best lap as read when the session was entered (#353).
    public var corners: [CornerRecord]
    /// Which measurement read `corners` (#438): below `LogbookEntry.cornerMeasurement`, they were
    /// read by a build since corrected, and Trends offers to read them again.
    public var cornerMeasurement: Int
    /// Which reading produced `laps` and what is worked out from them (#498): below
    /// `LogbookEntry.lapMeasurement`, the file was read by a build since corrected, and the Logbook
    /// offers to read it again.
    public var lapMeasurement: Int
    /// The track day the session belongs to (#392); `nil` only until `Logbook.ensureDays` runs.
    public var trackDayID: UUID?
    /// How long the file runs, from its first sample to its last (#392), so a clip can be matched
    /// to it by clock without reading the file again.
    public var durationSeconds: Double?
    /// What the Coaching window last read of this session with no project (#396): the lap, the
    /// reference, the alignment. Its `dataInputID` is the entry's own id.
    public var coaching: CoachingSettings?
    /// The start and finish its file is timed in runs between (#552); `nil` for a circuit's laps.
    public var runLines: RunLines?
    /// The course the runs were driven on (#552), which its personal bests and Trends are kept for.
    public var course: CourseTag?
    /// The best run's path, every few metres, to tell whether another session's runs were on the
    /// same course. Empty for laps.
    public var coursePath: [CoursePoint] = []
    /// Seconds a cone adds to a run (#552), as its track day says; `nil` is the usual 2 s.
    public var penaltyPerCone: Double?
    public var added: Date
    public var modified: Date

    public init(
        id: UUID = UUID(), file: SourceFile, circuitID: String? = nil, trackName: String? = nil, date: Date? = nil,
        car: String = "", driver: String = "", laps: [LapRecord] = [], bestLap: Double? = nil,
        bestLapNumber: Int? = nil, optimalLap: Double? = nil, fastestRollingLap: Double? = nil,
        topSpeed: Double? = nil, distanceMeters: Double? = nil, notes: String = "", tags: [String] = [],
        conditions: SessionConditions = SessionConditions(), projects: [ProjectLink] = [], exports: [ProjectLink] = [],
        corners: [CornerRecord] = [], trackDayID: UUID? = nil, durationSeconds: Double? = nil,
        coaching: CoachingSettings? = nil, added: Date = Date(), modified: Date = Date()
    ) {
        self.id = id
        self.file = file
        self.circuitID = circuitID
        self.trackName = trackName
        self.date = date
        self.car = car
        self.driver = driver
        self.laps = laps
        self.bestLap = bestLap
        self.bestLapNumber = bestLapNumber
        self.optimalLap = optimalLap
        self.fastestRollingLap = fastestRollingLap
        self.topSpeed = topSpeed
        self.distanceMeters = distanceMeters
        self.notes = notes
        self.tags = tags
        self.conditions = conditions
        self.projects = projects
        self.exports = exports
        self.corners = corners
        self.cornerMeasurement = Self.cornerMeasurement
        self.lapMeasurement = Self.lapMeasurement
        self.trackDayID = trackDayID
        self.durationSeconds = durationSeconds
        self.coaching = coaching
        self.added = added
        self.modified = modified
    }

    public var completeLapCount: Int { laps.filter(\.isComplete).count }

    /// Whether its file is timed in runs of a point-to-point course (#552) rather than laps.
    public var isRuns: Bool { runLines != nil }

    /// How to read its file again: with the importer that read it first, and in runs between its
    /// lines when it is timed in runs, so a reference, a personal best or a re-reading of its laps
    /// sees the same laps the logbook lists.
    public var readingSettings: DataInputSettings {
        var settings = DataInputSettings()
        settings.importerID = file.importerID
        settings.lapLine = runLines?.start
        settings.runFinishLine = runLines?.finish
        return settings
    }

    /// "Sonoma", else the file's track name, else the file's name.
    /// "Lot 4 – Course of 12 Oct 2026" for runs (#552), the circuit's name for laps.
    public var title: String {
        guard let course else { return venueTitle }
        // A car park nobody named is its course.
        guard circuitID != nil || !(trackName ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
            return course.name
        }
        return venueTitle + " – " + course.name
    }

    /// Where it was driven, without the course: the circuit, the track name the file gives, or the
    /// file's own name.
    public var venueTitle: String {
        if let circuitID, let circuit = CircuitCatalog.circuit(id: circuitID) { return circuit.name }
        if let trackName, !trackName.isEmpty { return trackName }
        return URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
    }

    /// The year the session was driven, for grouping; `nil` when the date is unknown.
    public var year: Int? { date.map { Calendar(identifier: .gregorian).component(.year, from: $0) } }

    /// The file, wherever it is now: the bookmark first, the path when the bookmark fails.
    public func resolveFile() -> URL? {
        if let bookmark = file.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale),
                FileManager.default.fileExists(atPath: url.path)
            {
                return url
            }
        }
        let url = URL(fileURLWithPath: file.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a project's data input, whose file is at `url`, is this session (#462). The input
    /// remembers the entry it came from (`DataInputSettings.logbookEntryID`); one that remembers
    /// none — the project entered nothing in the logbook, or has not finished loading — is the
    /// session when its file is the entry's.
    public func isSession(of input: Input, at url: URL) -> Bool {
        guard let settings = input.dataSettings else { return false }
        if let remembered = settings.logbookEntryID { return remembered == id }
        let own = resolveFile() ?? URL(fileURLWithPath: file.path)
        return own.resolvingSymlinksInPath().standardizedFileURL.path
            == url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private enum CodingKeys: String, CodingKey {
        case id, file, circuitID, trackName, date, car, driver, laps, bestLap, bestLapNumber, optimalLap
        case fastestRollingLap, topSpeed, distanceMeters, notes, tags, conditions, projects, exports, corners
        case cornerMeasurement, lapMeasurement, trackDayID, durationSeconds, coaching, added, modified
        case runLines, course, coursePath, penaltyPerCone
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        file = try c.decode(SourceFile.self, forKey: .file)
        circuitID = try c.decodeIfPresent(String.self, forKey: .circuitID)
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        car = try c.decodeIfPresent(String.self, forKey: .car) ?? ""
        driver = try c.decodeIfPresent(String.self, forKey: .driver) ?? ""
        laps = try c.decodeIfPresent([LapRecord].self, forKey: .laps) ?? []
        bestLap = try c.decodeIfPresent(Double.self, forKey: .bestLap)
        bestLapNumber = try c.decodeIfPresent(Int.self, forKey: .bestLapNumber)
        optimalLap = try c.decodeIfPresent(Double.self, forKey: .optimalLap)
        fastestRollingLap = try c.decodeIfPresent(Double.self, forKey: .fastestRollingLap)
        topSpeed = try c.decodeIfPresent(Double.self, forKey: .topSpeed)
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        conditions = try c.decodeIfPresent(SessionConditions.self, forKey: .conditions) ?? SessionConditions()
        projects = try c.decodeIfPresent([ProjectLink].self, forKey: .projects) ?? []
        exports = try c.decodeIfPresent([ProjectLink].self, forKey: .exports) ?? []
        corners = try c.decodeIfPresent([CornerRecord].self, forKey: .corners) ?? []
        // Absent in entries written before #438: their corners came from the first measurement.
        cornerMeasurement = try c.decodeIfPresent(Int.self, forKey: .cornerMeasurement) ?? 1
        // Absent in entries written before #498: their laps came from the first reading.
        lapMeasurement = try c.decodeIfPresent(Int.self, forKey: .lapMeasurement) ?? 1
        trackDayID = try c.decodeIfPresent(UUID.self, forKey: .trackDayID)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        coaching = try? c.decodeIfPresent(CoachingSettings.self, forKey: .coaching)
        // Absent before runs (#552): every such session was read as laps.
        runLines = try c.decodeIfPresent(RunLines.self, forKey: .runLines)
        course = try c.decodeIfPresent(CourseTag.self, forKey: .course)
        coursePath = try c.decodeIfPresent([CoursePoint].self, forKey: .coursePath) ?? []
        penaltyPerCone = try c.decodeIfPresent(Double.self, forKey: .penaltyPerCone)
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? Date(timeIntervalSince1970: 0)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? added
    }
}

extension LogbookEntry {
    /// An entry for `session`, read from `url` by `importerID`: the laps and their times, the
    /// best, optimal and fastest rolling lap, the circuit when `circuit` says so, the date from
    /// the file, and a hash and bookmark of the file. `car` and `driver` default to what the file
    /// says about the driver and nothing about the car.
    public static func make(
        session: TelemetrySession, file url: URL, importerID: String, circuitID: String?, car: String = "",
        driver: String? = nil
    ) throws -> LogbookEntry {
        let (hash, bytes) = try Self.hash(of: url)
        let bookmark =
            (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        let source = SourceFile(
            path: url.path, bookmark: bookmark, contentHash: hash, byteCount: bytes, importerID: importerID)
        let stats = SessionStats(session: session)
        var entry = LogbookEntry(
            file: source, circuitID: circuitID, trackName: session.info.trackName, date: session.info.createdAt,
            car: car, driver: driver ?? session.info.driverName ?? "",
            topSpeed: stats.topSpeed, distanceMeters: distance(of: session),
            durationSeconds: session.duration > 0 ? session.duration : nil)
        entry.readLaps(of: session)
        return entry
    }

    /// The reading the laps of an entry are from. 2 (#477): a RaceChrono file's first lap begins
    /// at the first crossing of the line and is a whole lap — read from an `.rcz` archive it had
    /// swallowed the out-lap, and from a CSV it was called partial.
    public static let lapMeasurement = 2

    /// Whether the Logbook should offer to read this entry's file again (#498): it was read
    /// before the first lap was corrected, and it is one the correction can change — an archive,
    /// or a file whose first lap was called partial. A file it cannot change is not offered:
    /// reading it again would cost the time and move nothing. Laps that begin at lap 0 are not
    /// the file's own count but the app's, from a start/finish line; the correction is not about
    /// them, and read again without that line they would be lost.
    public var needsLapReading: Bool {
        guard lapMeasurement < Self.lapMeasurement, let first = laps.first, first.number != 0 else { return false }
        return file.importerID == "racechrono-rcz" || !first.isComplete
    }

    /// Reads the laps of `session` into the entry with this build's reading, and with them what
    /// is worked out from the laps: the best, the optimal and the fastest rolling lap, and the
    /// corners of the best lap, which may be another lap now. Nothing the driver wrote — the car,
    /// the conditions, the notes — is touched.
    public mutating func readLaps(of session: TelemetrySession) {
        let stats = SessionStats(session: session)
        // Cones and an off-course are the driver's (#552): a run keeps them when its file is read again.
        let penalties = Dictionary(laps.map { ($0.number, ($0.cones, $0.offCourse)) }, uniquingKeysWith: { a, _ in a })
        laps = session.laps.listed.map { lap in
            let kept = penalties[lap.number]
            return LapRecord(
                number: lap.number, seconds: lap.duration, isComplete: lap.isComplete, cones: kept?.0 ?? 0,
                offCourse: kept?.1 ?? false)
        }
        bestLap = stats.bestLap?.seconds
        bestLapNumber = stats.bestLap?.number
        optimalLap = stats.optimalLap
        fastestRollingLap = CoachingReference.fastestRolling.resolve(in: session)?.duration
        lapMeasurement = Self.lapMeasurement
        applyPenalties()
        readCorners(of: session)
    }

    /// How far the session drove, from its distance channel; `nil` without one.
    public static func distance(of session: TelemetrySession) -> Double? {
        guard let channel = session[.distance], let low = channel.minValue, let high = channel.maxValue, high > low
        else { return nil }
        return high - low
    }

    /// SHA-256 of the file, streamed, and its length.
    public static func hash(of url: URL) throws -> (hex: String, byteCount: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += chunk.count
        }
        let digest = hasher.finalize()
        return (digest.map { String(format: "%02x", $0) }.joined(), total)
    }
}

/// A car in the garage (#345): a name and whatever the owner wants to say about it.
public struct Car: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String

    public init(id: UUID = UUID(), name: String, notes: String = "") {
        self.id = id
        self.name = name
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, name, notes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

/// The logbook on disk: one `.onboardsession` JSON file per entry and a `garage.json`, in
/// `~/Library/Application Support/OnboardStudio/Logbook` beside the track library — separate
/// files, as the tracks are, so a season can be copied, backed up or handed over as files.
/// Local only: nothing is uploaded.
public struct Logbook: Sendable {
    public static let fileExtension = "onboardsession"
    public static let garageFileName = "garage.json"

    public let directory: URL

    /// Defaults to the Application Support folder. Tests pass their own.
    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "OnboardStudio/Logbook")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "OnboardStudio/Logbook")
    }

    public func url(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).\(Self.fileExtension)") }

    /// Every entry, newest session first (undated last). Unreadable files are skipped.
    public func entries() -> [LogbookEntry] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { try? Self.read(from: $0) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public func entry(id: UUID) -> LogbookEntry? { try? Self.read(from: url(for: id)) }

    /// The entry made from a file with these bytes, if any: how the same file is never added twice.
    public func entry(forContentHash hash: String) -> LogbookEntry? {
        entries().first { $0.file.contentHash == hash }
    }

    /// Writes the entry, stamping `modified` with now — unless `keepingModified`, for an entry
    /// arriving from elsewhere whose own date is the truth (#350).
    public func save(_ entry: LogbookEntry, keepingModified: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var stamped = entry
        if !keepingModified { stamped.modified = Date() }
        try Self.write(stamped, to: url(for: entry.id))
    }

    public func remove(id: UUID) throws {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    // MARK: - The garage

    public func cars() -> [Car] {
        guard let data = try? Data(contentsOf: directory.appending(path: Self.garageFileName)) else { return [] }
        return (try? Self.decoder.decode([Car].self, from: data)) ?? []
    }

    public func saveCars(_ cars: [Car]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(cars).write(to: directory.appending(path: Self.garageFileName), options: .atomic)
    }

    // MARK: - The files themselves

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func read(from url: URL) throws -> LogbookEntry {
        try decoder.decode(LogbookEntry.self, from: Data(contentsOf: url))
    }

    public static func write(_ entry: LogbookEntry, to url: URL) throws {
        try encoder.encode(entry).write(to: url, options: .atomic)
    }
}

extension LogbookEntry.LapRecord {
    private enum CodingKeys: String, CodingKey { case number, seconds, isComplete, cones, offCourse }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let number = try c.decode(Int.self, forKey: .number)
        let seconds = try c.decodeIfPresent(Double.self, forKey: .seconds)
        let isComplete = try c.decode(Bool.self, forKey: .isComplete)
        // Absent before cones (#552): nothing was penalised.
        self.init(
            number: number, seconds: seconds, isComplete: isComplete,
            cones: try c.decodeIfPresent(Int.self, forKey: .cones) ?? 0,
            offCourse: try c.decodeIfPresent(Bool.self, forKey: .offCourse) ?? false)
    }
}
