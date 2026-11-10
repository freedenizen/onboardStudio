import Foundation
import TelemetryKit

/// One day at a circuit (#392): where, when, what was driven, the conditions, and the clips
/// the camera recorded — the thing the sessions of that day hang from. A day can be made before
/// any file exists, so a driver begins the day in the logbook and adds sessions as they come
/// off the logger.
public struct TrackDay: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// The day, as the start of that day in the local calendar.
    public var date: Date
    /// Wikidata id of the circuit when recognised or chosen from the catalogue.
    public var circuitID: String?
    /// The circuit's name as typed when it is not in the catalogue.
    public var trackName: String?
    public var car: String
    public var driver: String
    public var notes: String
    public var tags: [String]
    /// The day's conditions, the default for a session added to it; a session can differ.
    public var conditions: SessionConditions
    /// The camera clips of the day, matched to its sessions (#394).
    public var clips: [ClipRecord]
    public var added: Date
    public var modified: Date

    public init(
        id: UUID = UUID(), date: Date, circuitID: String? = nil, trackName: String? = nil, car: String = "",
        driver: String = "", notes: String = "", tags: [String] = [],
        conditions: SessionConditions = SessionConditions(),
        clips: [ClipRecord] = [], added: Date = Date(), modified: Date = Date()
    ) {
        self.id = id
        self.date = Self.startOfDay(date)
        self.circuitID = circuitID
        self.trackName = trackName
        self.car = car
        self.driver = driver
        self.notes = notes
        self.tags = tags
        self.conditions = conditions
        self.clips = clips
        self.added = added
        self.modified = modified
    }

    /// "Sonoma", else the name typed, else "Track day".
    public var title: String {
        if let circuitID, let circuit = CircuitCatalog.circuit(id: circuitID) { return circuit.name }
        if let trackName, !trackName.isEmpty { return trackName }
        return "Track day"
    }

    /// "23 Aug 2026 · Sonoma": how the sidebar and a report line name the day.
    public var label: String { "\(date.formatted(date: .abbreviated, time: .omitted)) · \(title)" }

    public var year: Int { Calendar(identifier: .gregorian).component(.year, from: date) }

    /// What a day is grouped by: its circuit (catalogue id, else the name typed, else nothing).
    public var circuitKey: String { circuitID ?? trackName ?? "" }

    public static func startOfDay(_ date: Date) -> Date { Calendar(identifier: .gregorian).startOfDay(for: date) }

    private enum CodingKeys: String, CodingKey {
        case id, date, circuitID, trackName, car, driver, notes, tags, conditions, clips, added, modified
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        circuitID = try c.decodeIfPresent(String.self, forKey: .circuitID)
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        car = try c.decodeIfPresent(String.self, forKey: .car) ?? ""
        driver = try c.decodeIfPresent(String.self, forKey: .driver) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        conditions = try c.decodeIfPresent(SessionConditions.self, forKey: .conditions) ?? SessionConditions()
        clips = try c.decodeIfPresent([ClipRecord].self, forKey: .clips) ?? []
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? Date(timeIntervalSince1970: 0)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? added
    }
}

/// A camera clip of a track day (#394): the file, when the camera says it was recorded and for
/// how long, and the session it belongs to. A recording of several GoPro chapters is one clip
/// with the following chapters listed.
public struct ClipRecord: Identifiable, Hashable, Codable, Sendable {
    /// How the clip came to be the session's.
    public enum Match: String, Codable, Sendable {
        /// The camera's clock put it inside the session's time.
        case clock
        /// Nothing on the clocks, but the day had one session.
        case onlySessionThatDay
        /// The user said so.
        case byHand
    }

    public var id: UUID
    public var path: String
    public var bookmark: Data?
    public var byteCount: Int
    /// SHA-256 of the first mebibyte and the length, hex: enough to know the file again
    /// without reading a 20 GB clip through.
    public var fingerprint: String
    /// The chapters that follow this one (`GX020037.MP4` after `GX010037.MP4`), in order.
    public var chapterPaths: [String]
    /// The whole recording, every chapter.
    public var durationSeconds: Double?
    /// When the camera started recording, by its own clock.
    public var recordedAt: Date?
    /// Where that clock came from: "GoPro GPS clock", "file creation time"…
    public var clock: String?
    public var hasGPS: Bool
    /// The logbook session it belongs to, when matched.
    public var sessionID: UUID?
    public var matchedBy: Match?

    public init(
        id: UUID = UUID(), path: String, bookmark: Data? = nil, byteCount: Int, fingerprint: String,
        chapterPaths: [String] = [], durationSeconds: Double? = nil, recordedAt: Date? = nil, clock: String? = nil,
        hasGPS: Bool = false, sessionID: UUID? = nil, matchedBy: Match? = nil
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.byteCount = byteCount
        self.fingerprint = fingerprint
        self.chapterPaths = chapterPaths
        self.durationSeconds = durationSeconds
        self.recordedAt = recordedAt
        self.clock = clock
        self.hasGPS = hasGPS
        self.sessionID = sessionID
        self.matchedBy = matchedBy
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }

    /// The file, wherever it is now: the bookmark first, the path when the bookmark fails.
    public func resolveFile() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale),
                FileManager.default.fileExists(atPath: url.path)
            {
                return url
            }
        }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, bookmark, byteCount, fingerprint, chapterPaths, durationSeconds, recordedAt, clock, hasGPS
        case sessionID, matchedBy
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        byteCount = try c.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        chapterPaths = try c.decodeIfPresent([String].self, forKey: .chapterPaths) ?? []
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt)
        clock = try c.decodeIfPresent(String.self, forKey: .clock)
        hasGPS = try c.decodeIfPresent(Bool.self, forKey: .hasGPS) ?? false
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
        matchedBy = try? c.decodeIfPresent(Match.self, forKey: .matchedBy)
    }
}

// MARK: - Days in the logbook

extension Logbook {
    public static let dayFileExtension = "onboardday"

    public func url(forDay id: UUID) -> URL { directory.appending(path: "\(id.uuidString).\(Self.dayFileExtension)") }

    /// Every day, newest first. Unreadable files are skipped.
    public func days() -> [TrackDay] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { $0.pathExtension == Self.dayFileExtension }
            .compactMap { try? Self.readDay(from: $0) }
            .sorted { ($0.date, $0.added) > ($1.date, $1.added) }
    }

    public func day(id: UUID) -> TrackDay? { try? Self.readDay(from: url(forDay: id)) }

    /// Writes the day, stamping `modified` with now — unless `keepingModified`, for a day
    /// arriving from elsewhere whose own date is the truth.
    public func saveDay(_ day: TrackDay, keepingModified: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var stamped = day
        if !keepingModified { stamped.modified = Date() }
        try Self.writeDay(stamped, to: url(forDay: day.id))
    }

    /// Writes an edited day and carries a change of its car or driver to its sessions (#453).
    /// A session takes the day's car when it is added, and it kept that copy whatever the day
    /// said afterwards: a typo corrected on the day left every session under the old name, and a
    /// car typed on a day made by a files-first import left them all under none. A session that
    /// still has what the day had follows the day; one given a car or driver of its own keeps it.
    /// Returns the sessions changed.
    @discardableResult
    public func updateDay(_ day: TrackDay) throws -> [LogbookEntry] {
        let old = self.day(id: day.id)
        try saveDay(day)
        guard let old, old.car != day.car || old.driver != day.driver else { return [] }
        var changed: [LogbookEntry] = []
        for var entry in sessions(of: day) {
            let before = entry
            if old.car != day.car, entry.car == old.car { entry.car = day.car }
            if old.driver != day.driver, entry.driver == old.driver { entry.driver = day.driver }
            guard entry != before else { continue }
            try save(entry)
            changed.append(entry)
        }
        return changed
    }

    /// Takes the day out; with `andSessions`, its sessions too. No file of the user's is touched.
    public func removeDay(id: UUID, andSessions: Bool = false) throws {
        if andSessions {
            for entry in entries() where entry.trackDayID == id { try remove(id: entry.id) }
        }
        let file = url(forDay: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// The day's sessions, newest first.
    public func sessions(of day: TrackDay) -> [LogbookEntry] { entries().filter { $0.trackDayID == day.id } }

    /// The day an entry belongs on by its calendar day and circuit: found among the days there
    /// are, else made now from the entry (its car and driver copied) and saved.
    public func day(for entry: LogbookEntry) throws -> TrackDay {
        if let id = entry.trackDayID, let day = day(id: id) { return day }
        return try day(
            on: entry.date ?? entry.added, circuitID: entry.circuitID,
            trackName: entry.circuitID == nil ? entry.trackName : nil, car: entry.car, driver: entry.driver)
    }

    /// The day on `date` at the circuit, found or made (#394): a clip with no session of its own
    /// still goes on a day. With no circuit, the day on that date with the most sessions, else a
    /// day with no circuit.
    public func day(
        on date: Date, circuitID: String? = nil, trackName: String? = nil, car: String = "", driver: String = ""
    ) throws -> TrackDay {
        let when = TrackDay.startOfDay(date)
        let key = circuitID ?? trackName ?? ""
        let that = days().filter { $0.date == when }
        if let found = that.first(where: { $0.circuitKey == key }) { return found }
        if key.isEmpty, !that.isEmpty {
            let counts = Dictionary(grouping: entries().compactMap(\.trackDayID), by: { $0 }).mapValues(\.count)
            if let busiest = that.max(by: { (counts[$0.id] ?? 0) < (counts[$1.id] ?? 0) }) { return busiest }
        }
        let made = TrackDay(date: when, circuitID: circuitID, trackName: trackName, car: car, driver: driver)
        try saveDay(made)
        return made
    }

    /// Every entry with no day is put on one (#392): entries from before days existed, or
    /// written by a build without them. Returns how many were placed. Idempotent.
    @discardableResult
    public func ensureDays() throws -> Int {
        var placed = 0
        for var entry in entries() where entry.trackDayID.flatMap({ day(id: $0) }) == nil {
            entry.trackDayID = nil
            entry.trackDayID = try day(for: entry).id
            try save(entry, keepingModified: true)
            placed += 1
        }
        return placed
    }

    public static func readDay(from url: URL) throws -> TrackDay {
        try decoder.decode(TrackDay.self, from: Data(contentsOf: url))
    }

    public static func writeDay(_ day: TrackDay, to url: URL) throws {
        try encoder.encode(day).write(to: url, options: .atomic)
    }
}
