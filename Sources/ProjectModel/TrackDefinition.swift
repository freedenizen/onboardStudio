import Foundation

/// What was worked out about a circuit once, kept so the next visit does not start from nothing:
/// the start/finish line, how the lap is split into sectors, and what to call the place.
///
/// No licence covers sector geometry — no open source publishes it and no logger format carries
/// it (`docs/tracks-and-sectors.md`) — so a definition the driver writes, keeps and passes on is
/// the only route to a shared library, and being contributor-owned it carries no licensing
/// problem at all.
public struct TrackDefinition: Hashable, Codable, Sendable, Identifiable {
    /// Wikidata circuit id (`Q112563`) when the venue is in the bundled list, `nil` when it is
    /// not — a club circuit, a car park, an airfield.
    public var circuitID: String?
    /// What to call it. Seeded from the circuit list or from the file, and editable, because the
    /// driver's name for a place beats a database's.
    public var name: String
    /// Where it is, so a session with no track name can still be matched to it.
    public var latitude: Double
    public var longitude: Double
    public var startFinish: LapLineSpec?
    public var sectors: SectorSpec
    /// What the circuit calls its corners, in driving order from the start/finish.
    ///
    /// The reason a definition is worth sharing: no source publishes corner numbering, so one
    /// driver working out that Sonoma goes 3, 3a, 4, 4a saves everyone else doing it.
    public var cornerLabels: [String]
    /// When it was last written. Two drivers swapping definitions need to know which is newer.
    public var modified: Date

    public init(
        circuitID: String? = nil,
        name: String,
        latitude: Double,
        longitude: Double,
        startFinish: LapLineSpec? = nil,
        sectors: SectorSpec = SectorSpec(),
        cornerLabels: [String] = [],
        modified: Date = Date()
    ) {
        self.circuitID = circuitID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.startFinish = startFinish
        self.sectors = sectors
        self.cornerLabels = cornerLabels
        self.modified = modified
    }

    /// What the definition is filed under: the Wikidata id where there is one, otherwise a slug
    /// of the name. The id is preferred because circuits get renamed by sponsors — Laguna Seca
    /// twice — and a definition should survive that.
    public var id: String { circuitID ?? Self.slug(name) }

    /// Lowercased, accents folded, and runs of anything else collapsed to a single `-`, so the
    /// key is a safe file name and the same name always produces the same one.
    public static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var result = ""
        var pendingSeparator = false
        for character in folded {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !result.isEmpty { result.append("-") }
                pendingSeparator = false
                result.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return result.isEmpty ? "track" : String(result.prefix(64))
    }

    private enum CodingKeys: String, CodingKey {
        case circuitID, name, latitude, longitude, startFinish, sectors, cornerLabels, modified
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        circuitID = try c.decodeIfPresent(String.self, forKey: .circuitID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Track"
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        startFinish = try c.decodeIfPresent(LapLineSpec.self, forKey: .startFinish)
        sectors = try c.decodeIfPresent(SectorSpec.self, forKey: .sectors) ?? SectorSpec()
        cornerLabels = try c.decodeIfPresent([String].self, forKey: .cornerLabels) ?? []
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Track definitions on disk, one JSON file each.
///
/// Deliberately a directory of separate files rather than one database: a definition is meant to
/// be handed to another driver, and a file you can attach to a message is the whole point.
public struct TrackLibrary: Sendable {
    public static let fileExtension = "onboardtrack"

    public let directory: URL

    /// Defaults to `~/Library/Application Support/OnboardStudio/Tracks`. Tests pass their own.
    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "OnboardStudio/Tracks")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "OnboardStudio/Tracks")
    }

    public func url(for id: String) -> URL {
        directory.appending(path: "\(TrackDefinition.slug(id)).\(Self.fileExtension)")
    }

    /// The definition filed under `id`, or `nil`. Never throws: a library that cannot be read is
    /// a library with nothing in it, not a reason to fail opening a project.
    public func definition(id: String) -> TrackDefinition? {
        try? Self.read(from: url(for: id))
    }

    /// Every definition, newest first. Unreadable files are skipped.
    public func all() -> [TrackDefinition] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return
            contents
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { try? Self.read(from: $0) }
            .sorted { $0.modified > $1.modified }
    }

    public func save(_ definition: TrackDefinition) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var stamped = definition
        stamped.modified = Date()
        try Self.write(stamped, to: url(for: definition.id))
    }

    public func remove(id: String) throws {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    // MARK: - The file itself

    public static func read(from url: URL) throws -> TrackDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrackDefinition.self, from: Data(contentsOf: url))
    }

    public static func write(_ definition: TrackDefinition, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(definition).write(to: url, options: .atomic)
    }
}
