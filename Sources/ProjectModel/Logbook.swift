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

        public init(number: Int, seconds: Double?, isComplete: Bool) {
            self.number = number
            self.seconds = seconds
            self.isComplete = isComplete
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
    /// The track day the session belongs to (#392); `nil` only until `Logbook.ensureDays` runs.
    public var trackDayID: UUID?
    /// How long the file runs, from its first sample to its last (#392), so a clip can be matched
    /// to it by clock without reading the file again.
    public var durationSeconds: Double?
    /// What the Coaching window last read of this session with no project (#396): the lap, the
    /// reference, the alignment. Its `dataInputID` is the entry's own id.
    public var coaching: CoachingSettings?
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
        self.trackDayID = trackDayID
        self.durationSeconds = durationSeconds
        self.coaching = coaching
        self.added = added
        self.modified = modified
    }

    public var completeLapCount: Int { laps.filter(\.isComplete).count }

    /// "Sonoma", else the file's track name, else the file's name.
    public var title: String {
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

    private enum CodingKeys: String, CodingKey {
        case id, file, circuitID, trackName, date, car, driver, laps, bestLap, bestLapNumber, optimalLap
        case fastestRollingLap, topSpeed, distanceMeters, notes, tags, conditions, projects, exports, corners
        case cornerMeasurement, trackDayID, durationSeconds, coaching, added, modified
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
        trackDayID = try c.decodeIfPresent(UUID.self, forKey: .trackDayID)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        coaching = try? c.decodeIfPresent(CoachingSettings.self, forKey: .coaching)
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
        let rolling = CoachingReference.fastestRolling.resolve(in: session)?.duration
        let laps = session.laps.map { LapRecord(number: $0.number, seconds: $0.duration, isComplete: $0.isComplete) }
        return LogbookEntry(
            file: source, circuitID: circuitID, trackName: session.info.trackName, date: session.info.createdAt,
            car: car, driver: driver ?? session.info.driverName ?? "", laps: laps, bestLap: stats.bestLap?.seconds,
            bestLapNumber: stats.bestLap?.number, optimalLap: stats.optimalLap, fastestRollingLap: rolling,
            topSpeed: stats.topSpeed, distanceMeters: distance(of: session), corners: cornerRecords(of: session),
            durationSeconds: session.duration > 0 ? session.duration : nil)
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
