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

    public init(
        id: UUID = UUID(), name: String, notes: String = "", setups: [SavedSetup] = [], startingSetupID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.setups = setups
        self.startingSetupID = startingSetupID
    }

    /// The setup a new session starts with, if one is marked and still kept.
    public var startingSetup: SavedSetup? { startingSetupID.flatMap { id in setups.first { $0.id == id } } }

    private enum CodingKeys: String, CodingKey { case id, name, notes, setups, startingSetupID }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        setups = try c.decodeIfPresent([SavedSetup].self, forKey: .setups) ?? []
        startingSetupID = try c.decodeIfPresent(UUID.self, forKey: .startingSetupID)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(notes, forKey: .notes)
        // A car with no setups is written as an earlier build wrote it.
        if !setups.isEmpty { try c.encode(setups, forKey: .setups) }
        try c.encodeIfPresent(startingSetupID, forKey: .startingSetupID)
    }
}
