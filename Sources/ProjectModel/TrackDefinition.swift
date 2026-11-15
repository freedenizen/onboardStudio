import Foundation
import TelemetryKit

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
    /// Which of the circuit's configurations this is (#549): "Club Course". `nil` for the circuit's
    /// unnamed configuration, which is every definition saved before configurations existed.
    public var configuration: String?
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
    /// The turn names pinned to their apexes (#548), which name the corners in place of
    /// `cornerLabels` when there are any. A definition saved before has none.
    public var turnNames: [TurnName]
    /// When it was last written. Two drivers swapping definitions need to know which is newer.
    public var modified: Date
    /// What the driver planned to try next time here (#330), kept so the next project at this
    /// circuit opens knowing it.
    public var plan: NextSessionPlan?
    /// Who made a definition that ships with the app, and under what licence (#584): "LapViz
    /// (Mengal SRL), MIT". `nil` for the driver's own and for every file saved before.
    public var credit: String?

    public init(
        circuitID: String? = nil,
        configuration: String? = nil,
        name: String,
        latitude: Double,
        longitude: Double,
        startFinish: LapLineSpec? = nil,
        sectors: SectorSpec = SectorSpec(),
        cornerLabels: [String] = [],
        turnNames: [TurnName] = [],
        modified: Date = Date(),
        plan: NextSessionPlan? = nil
    ) {
        self.circuitID = circuitID
        self.configuration = configuration.map(CircuitKey.cleaned).flatMap { $0.isEmpty ? nil : $0 }
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.startFinish = startFinish
        self.sectors = sectors
        self.cornerLabels = cornerLabels
        self.turnNames = turnNames
        self.modified = modified
        self.plan = plan
    }

    /// What the definition is filed under: the Wikidata id where there is one, otherwise a slug
    /// of the name. The id is preferred because circuits get renamed by sponsors — Laguna Seca
    /// twice — and a definition should survive that.
    ///
    /// A configuration is filed beside its circuit (`CircuitKey`), so the unnamed configuration —
    /// every definition saved before #549 — keeps the file it always had.
    /// "Sonoma Raceway — Club Course" (#549).
    public var title: String { CircuitKey.title(name, configuration: configuration) }

    public var id: String { CircuitKey.make(circuitID ?? Self.slug(name), configuration: configuration) }

    /// Whether the definition says anything about the circuit's shape: a start/finish line,
    /// sectors or corner names. One that only keeps a plan — made from the Logbook, or from a file
    /// that brought its own laps — says nothing, and a new file at the circuit is set up as if
    /// there were no definition: its start/finish is suggested from the trace (#458).
    public var hasGeometry: Bool {
        startFinish != nil || sectors != SectorSpec() || !cornerLabels.isEmpty || !turnNames.isEmpty
    }

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
        case circuitID, configuration, name, latitude, longitude, startFinish, sectors, cornerLabels, turnNames,
            modified, plan, credit
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        circuitID = try c.decodeIfPresent(String.self, forKey: .circuitID)
        configuration = try c.decodeIfPresent(String.self, forKey: .configuration)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Track"
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        startFinish = try c.decodeIfPresent(LapLineSpec.self, forKey: .startFinish)
        sectors = try c.decodeIfPresent(SectorSpec.self, forKey: .sectors) ?? SectorSpec()
        cornerLabels = try c.decodeIfPresent([String].self, forKey: .cornerLabels) ?? []
        turnNames = try c.decodeIfPresent([TurnName].self, forKey: .turnNames) ?? []
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date(timeIntervalSince1970: 0)
        plan = try c.decodeIfPresent(NextSessionPlan.self, forKey: .plan)
        credit = try c.decodeIfPresent(String.self, forKey: .credit)
    }
}

/// Track definitions on disk, one JSON file each.
///
/// Deliberately a directory of separate files rather than one database: a definition is meant to
/// be handed to another driver, and a file you can attach to a message is the whole point.
///
/// Behind the driver's own folder there can be a second, read-only one: the definitions that ship
/// with the app (#584), contributed by drivers who know those circuits. The driver's own always
/// wins. Whatever is written — a plan, a name, a saved line — goes into the driver's folder,
/// starting from the shipped definition when that is all there was, and removing a definition
/// removes only the driver's copy, so the shipped one shows through again.
public struct TrackLibrary: Sendable {
    public static let fileExtension = "onboardtrack"

    public let directory: URL
    /// The definitions that ship with the app, read-only; `nil` for none.
    public let builtIn: URL?

    /// Defaults to `~/Library/Application Support/OnboardStudio/Tracks`. Tests pass their own.
    /// `builtIn` is none unless asked for: the app asks for `TrackLibrary.bundled`.
    public init(directory: URL? = nil, builtIn: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "OnboardStudio/Tracks")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "OnboardStudio/Tracks")
        self.builtIn = builtIn
    }

    /// The folder of definitions that ship with the app (#584).
    public static var bundled: URL? { Bundle.module.url(forResource: "Tracks", withExtension: nil) }

    public func url(for id: String) -> URL {
        directory.appending(path: "\(TrackDefinition.slug(id)).\(Self.fileExtension)")
    }

    /// The definition filed under `id`, the driver's own before the app's, or `nil`. Never throws:
    /// a library that cannot be read is a library with nothing in it, not a reason to fail opening
    /// a project.
    public func definition(id: String) -> TrackDefinition? {
        (try? Self.read(from: url(for: id))) ?? builtInDefinition(id: id)
    }

    /// Where the definition filed under `id` comes from.
    public enum Source: Sendable, Equatable {
        /// The driver's own: saved, imported or changed here.
        case yours
        /// One that ships with the app, which the driver has not changed.
        case builtIn
    }

    /// Whose the definition filed under `id` is; `nil` when there is none.
    public func source(of id: String) -> Source? {
        if (try? Self.read(from: url(for: id))) != nil { return .yours }
        return builtInDefinition(id: id) == nil ? nil : .builtIn
    }

    /// Every definition, the driver's own and the app's that the driver has not replaced, newest
    /// first. Unreadable files are skipped.
    public func all() -> [TrackDefinition] {
        let yours = Self.definitions(in: directory)
        let ids = Set(yours.map(\.id))
        let shipped = builtIn.map(Self.definitions(in:))?.filter { !ids.contains($0.id) } ?? []
        return (yours + shipped).sorted { $0.modified > $1.modified }
    }

    /// Whether a definition filed under `id` ships with the app, whether or not the driver has one.
    public func shipsDefinition(id: String) -> Bool { builtInDefinition(id: id) != nil }

    private func builtInDefinition(id: String) -> TrackDefinition? {
        guard let builtIn else { return nil }
        return try? Self.read(
            from: builtIn.appending(path: "\(TrackDefinition.slug(id)).\(Self.fileExtension)"))
    }

    private static func definitions(in folder: URL) -> [TrackDefinition] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == fileExtension }.compactMap { try? read(from: $0) }
    }

    /// Keeps `plan` on the definition saved as `id`, or on `fresh()` when there is none — a circuit
    /// planned for the first time. A definition that has the plan already is not written again.
    public func remember(_ plan: NextSessionPlan, id: String, fresh: () -> TrackDefinition?) throws {
        guard var definition = definition(id: id) ?? fresh(), definition.plan != plan else { return }
        definition.plan = plan
        definition.modified = Date()
        try save(definition)
    }

    /// Every configuration kept for the circuit `circuitID` (#549), the unnamed one included.
    public func configurations(of circuitID: String) -> [TrackDefinition] {
        all().filter { $0.circuitID == circuitID }
    }

    /// Takes the plan off the circuit's definition (#460): its last experiment removed on the
    /// Logbook's circuit card. The definition stays, with whatever else it holds.
    public func forgetPlan(id: String) throws {
        guard var definition = definition(id: id), definition.plan != nil else { return }
        definition.plan = nil
        try save(definition)
    }

    public func save(_ definition: TrackDefinition) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var stamped = definition
        stamped.modified = Date()
        try Self.write(stamped, to: url(for: definition.id))
    }

    /// Removes the driver's own definition filed under `id`; one that ships with the app, if any,
    /// is what `definition(id:)` gives from then on.
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
