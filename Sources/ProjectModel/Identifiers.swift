import Foundation

/// Stable identity of an input file within a project.
public struct InputID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UUID.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { rawValue.uuidString }
}

/// Stable identity of a display object within a project.
public struct DisplayObjectID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UUID.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { rawValue.uuidString }
}

/// Identity of a group of display objects that move, resize and nudge as one (#90).
public struct ObjectGroupID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UUID.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { rawValue.uuidString }
}
