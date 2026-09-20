import Foundation

/// Stable identity of a marker within a project.
public struct MarkerID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UUID.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { rawValue.uuidString }
}

/// A named point, or stretch, worth coming back to: a lap boundary, an incident, a sector.
///
/// Follows the model Resolve and Premiere agree on — colour, name, note, and an optional duration
/// that makes it a range rather than a flag. Final Cut's marker *types* are deliberately not
/// copied; they are Final Cut-specific and would not be expected by anyone else.
///
/// A marker either belongs to the timeline or to one input, which is Resolve's timeline-marker
/// versus clip-marker distinction. The difference is not cosmetic: an input's marker is stored in
/// that **input's own time**, so re-syncing or re-speeding the input carries its markers with it,
/// while a timeline marker stays where it is. Marking a braking point in the data and then fixing
/// the sync should move the mark with the data, not leave it behind.
public struct Marker: Hashable, Codable, Sendable, Identifiable {
    public var id: MarkerID
    /// The input this marker belongs to, or `nil` for a marker on the timeline itself.
    public var inputID: InputID?
    /// Seconds: project time for a timeline marker, the input's own time for an input's marker.
    public var time: Double
    /// Length in the same units; 0 draws a flag, more draws a bar.
    public var duration: Double
    public var name: String
    public var colour: RGBAColor
    public var note: String

    public static let defaultColour = RGBAColor(red: 1, green: 0.78, blue: 0.2, alpha: 1)

    public init(
        id: MarkerID = MarkerID(), inputID: InputID? = nil, time: Double, duration: Double = 0,
        name: String = "", colour: RGBAColor = Marker.defaultColour, note: String = ""
    ) {
        self.id = id
        self.inputID = inputID
        self.time = time
        self.duration = duration
        self.name = name
        self.colour = colour
        self.note = note
    }

    public var isRange: Bool { duration > 0 }
    public var end: Double { time + duration }

    private enum CodingKeys: String, CodingKey { case id, inputID, time, duration, name, colour, note }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(MarkerID.self, forKey: .id) ?? MarkerID()
        inputID = try c.decodeIfPresent(InputID.self, forKey: .inputID)
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colour = try c.decodeIfPresent(RGBAColor.self, forKey: .colour) ?? Marker.defaultColour
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// A marker with the place it falls on the project ruler worked out.
public struct PlacedMarker: Hashable, Sendable, Identifiable {
    public var id: MarkerID { marker.id }
    public let marker: Marker
    public let start: Double
    public let end: Double

    public init(marker: Marker, start: Double, end: Double) {
        self.marker = marker
        self.start = start
        self.end = end
    }
}

extension Project {
    /// Every marker in project time, in order, with each input's markers mapped through its sync.
    ///
    /// Markers are stored per input in the input's own time, so this is the one place that knows
    /// how to line them all up on a single ruler. A marker whose input has gone is dropped rather
    /// than drawn at the wrong place.
    public func markersInProjectTime() -> [PlacedMarker] {
        markers.compactMap { marker -> PlacedMarker? in
            guard let inputID = marker.inputID else {
                return PlacedMarker(marker: marker, start: marker.time, end: marker.end)
            }
            guard let input = input(inputID) else { return nil }
            return PlacedMarker(
                marker: marker, start: input.sync.projectTime(forInputTime: marker.time),
                end: input.sync.projectTime(forInputTime: marker.end))
        }
        .sorted { $0.start < $1.start }
    }

    /// The next marker strictly after `time`, for jump-to-next.
    ///
    /// Strictly after, so holding the shortcut walks the list instead of sticking on the marker
    /// the playhead is already sitting on. `epsilon` absorbs the rounding that scrubbing to a
    /// marker leaves behind.
    public func marker(after time: Double, epsilon: Double = 1e-6) -> PlacedMarker? {
        markersInProjectTime().first { $0.start > time + epsilon }
    }

    /// The nearest marker strictly before `time`.
    public func marker(before time: Double, epsilon: Double = 1e-6) -> PlacedMarker? {
        markersInProjectTime().last { $0.start < time - epsilon }
    }
}
