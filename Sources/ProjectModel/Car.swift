import Foundation

/// A car in the garage (#345): a name and whatever the owner wants to say about it.
public struct Car: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String
    /// Setups kept to load onto a session (#559).
    public var setups: [SavedSetup]
    /// The setup a new session in this car starts with, when it has none of its own.
    public var startingSetupID: UUID?
    /// The driver's scale on the grip the logbook has learned for the car (#558): 1 as learned,
    /// 1.05 when they know it has five percent more than it has shown.
    public var gripAdjustment: Double

    public init(
        id: UUID = UUID(), name: String, notes: String = "", setups: [SavedSetup] = [], startingSetupID: UUID? = nil,
        gripAdjustment: Double = 1
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.setups = setups
        self.startingSetupID = startingSetupID
        self.gripAdjustment = gripAdjustment
    }

    /// The setup a new session starts with, if one is marked and still kept.
    public var startingSetup: SavedSetup? { startingSetupID.flatMap { id in setups.first { $0.id == id } } }

    private enum CodingKeys: String, CodingKey { case id, name, notes, setups, startingSetupID, gripAdjustment }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        setups = try c.decodeIfPresent([SavedSetup].self, forKey: .setups) ?? []
        startingSetupID = try c.decodeIfPresent(UUID.self, forKey: .startingSetupID)
        let adjustment = try c.decodeIfPresent(Double.self, forKey: .gripAdjustment) ?? 1
        gripAdjustment = adjustment.isFinite && adjustment > 0 ? adjustment : 1
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(notes, forKey: .notes)
        // A car with no setups is written as an earlier build wrote it.
        if !setups.isEmpty { try c.encode(setups, forKey: .setups) }
        try c.encodeIfPresent(startingSetupID, forKey: .startingSetupID)
        if gripAdjustment != 1 { try c.encode(gripAdjustment, forKey: .gripAdjustment) }
    }
}
