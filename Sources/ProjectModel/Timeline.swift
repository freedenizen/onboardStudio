import Foundation

public struct SegmentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UUID.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { rawValue.uuidString }
}

/// The per-object properties a timeline segment can override. A `nil` field is inherited from the
/// previous segment (or the object itself before the first segment).
public struct ObjectOverride: Hashable, Codable, Sendable {
    // swiftlint:disable discouraged_optional_boolean
    /// `nil` means "inherit"; that third state is the whole point of an override.
    public var isVisible: Bool?
    public var frame: UnitRect?
    public var opacity: Double?

    public init(isVisible: Bool? = nil, frame: UnitRect? = nil, opacity: Double? = nil) {
        // swiftlint:enable discouraged_optional_boolean
        self.isVisible = isVisible
        self.frame = frame
        self.opacity = opacity
    }

    public var isEmpty: Bool { isVisible == nil && frame == nil && opacity == nil }

    public func apply(to object: inout DisplayObject) {
        if let isVisible { object.isVisible = isVisible }
        if let frame { object.frame = frame }
        if let opacity { object.opacity = opacity }
    }
}

/// The properties a segment can override, for badges and reset buttons.
public enum OverridableProperty: String, CaseIterable, Sendable {
    case isVisible
    case frame
    case opacity
}

/// A point on the project timeline from which some object properties change. Segments are kept
/// sorted by start time; the project's own object values apply before the first segment.
public struct Segment: Identifiable, Hashable, Codable, Sendable {
    public var id: SegmentID
    /// Project time in seconds at which the segment begins.
    public var start: Double
    public var label: String
    public var overrides: [DisplayObjectID: ObjectOverride]

    public init(
        id: SegmentID = SegmentID(), start: Double, label: String = "",
        overrides: [DisplayObjectID: ObjectOverride] = [:]
    ) {
        self.id = id
        self.start = start
        self.label = label
        self.overrides = overrides
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, label, overrides
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(SegmentID.self, forKey: .id) ?? SegmentID()
        start = try c.decode(Double.self, forKey: .start)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        // Dictionary keys that are not String/Int encode as arrays; use string keys for readable JSON.
        let raw = try c.decodeIfPresent([String: ObjectOverride].self, forKey: .overrides) ?? [:]
        var overrides: [DisplayObjectID: ObjectOverride] = [:]
        for (key, value) in raw {
            if let uuid = UUID(uuidString: key) { overrides[DisplayObjectID(uuid)] = value }
        }
        self.overrides = overrides
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(start, forKey: .start)
        try c.encode(label, forKey: .label)
        let raw = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue.uuidString, $0.value) })
        try c.encode(raw, forKey: .overrides)
    }
}

/// Segments in time order. Later segments inherit every property they do not set from earlier
/// ones, so a camera switch is one visibility override per camera in one segment.
public struct Timeline: Hashable, Codable, Sendable {
    public var segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = segments.sorted { $0.start < $1.start }
    }

    public static let empty = Timeline()

    public var isEmpty: Bool { segments.isEmpty }

    public func segment(_ id: SegmentID) -> Segment? { segments.first { $0.id == id } }

    /// The segment in effect at `time`, or `nil` before the first one.
    public func segment(at time: Double) -> Segment? {
        segments.last { $0.start <= time }
    }

    /// Segments in effect at `time`, earliest first.
    public func segments(upTo time: Double) -> [Segment] {
        segments.filter { $0.start <= time }
    }

    /// Start times that begin a new set of object states, always including 0.
    public func cutPoints(duration: Double) -> [Double] {
        var points: [Double] = [0]
        for segment in segments where segment.start > 0 && segment.start < duration {
            if points.last != segment.start { points.append(segment.start) }
        }
        return points
    }

    // MARK: - Resolution

    /// The objects as they appear at `time`: `base` with every override up to and including the
    /// segment in effect applied in order.
    public func resolve(_ base: [DisplayObject], at time: Double) -> [DisplayObject] {
        let active = segments(upTo: time)
        guard !active.isEmpty else { return base }
        return base.map { object in
            var resolved = object
            for segment in active {
                segment.overrides[object.id]?.apply(to: &resolved)
            }
            return resolved
        }
    }

    /// Whether `segment` itself sets `property` for `object` (as opposed to inheriting it).
    public func overrides(_ property: OverridableProperty, of object: DisplayObjectID, in segment: SegmentID) -> Bool {
        guard let override = self.segment(segment)?.overrides[object] else { return false }
        switch property {
        case .isVisible: return override.isVisible != nil
        case .frame: return override.frame != nil
        case .opacity: return override.opacity != nil
        }
    }

    // MARK: - Editing

    /// Adds a segment starting at `time`, or returns the existing one at exactly that time.
    @discardableResult
    public mutating func addSegment(at time: Double, label: String = "") -> SegmentID {
        if let existing = segments.first(where: { abs($0.start - time) < 0.0005 }) { return existing.id }
        let segment = Segment(start: max(0, time), label: label)
        segments.append(segment)
        segments.sort { $0.start < $1.start }
        return segment.id
    }

    public mutating func removeSegment(_ id: SegmentID) {
        segments.removeAll { $0.id == id }
    }

    /// Moves `id` to `newStart` and shifts every later segment by the same amount, keeping their
    /// relative spacing (RaceRender's behaviour). Never moves a segment before the previous one.
    public mutating func shiftSegment(_ id: SegmentID, to newStart: Double) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let floor = index > 0 ? segments[index - 1].start + 0.001 : 0
        let target = max(floor, newStart)
        let delta = target - segments[index].start
        guard delta != 0 else { return }
        for later in index..<segments.count {
            segments[later].start += delta
        }
    }

    public mutating func setOverride(_ override: ObjectOverride, for object: DisplayObjectID, in segment: SegmentID) {
        guard let index = segments.firstIndex(where: { $0.id == segment }) else { return }
        if override.isEmpty {
            segments[index].overrides[object] = nil
        } else {
            segments[index].overrides[object] = override
        }
    }

    /// Updates one property override in `segment`; pass `nil` to inherit it again.
    public mutating func update(
        _ property: OverridableProperty, for object: DisplayObjectID, in segment: SegmentID,
        _ change: (inout ObjectOverride) -> Void
    ) {
        guard let index = segments.firstIndex(where: { $0.id == segment }) else { return }
        var override = segments[index].overrides[object] ?? ObjectOverride()
        change(&override)
        _ = property
        segments[index].overrides[object] = override.isEmpty ? nil : override
    }

    /// Drops overrides for objects that no longer exist.
    public mutating func prune(keeping objects: [DisplayObjectID]) {
        let keep = Set(objects)
        for index in segments.indices {
            segments[index].overrides = segments[index].overrides.filter { keep.contains($0.key) }
        }
    }
}

// MARK: - Layout presets

/// Multi-camera arrangements written into the video objects' frames.
public enum LayoutPreset: String, CaseIterable, Sendable {
    case fullscreen
    case pictureInPicture
    case splitHorizontal
    case splitVertical
    case quad

    public var displayName: String {
        switch self {
        case .fullscreen: "Full screen"
        case .pictureInPicture: "Picture in picture"
        case .splitHorizontal: "Side by side"
        case .splitVertical: "Top and bottom"
        case .quad: "Quad"
        }
    }

    /// Frames for `count` cameras in draw order (first = main). Cameras beyond what the layout
    /// shows get `nil` (hide them).
    public func frames(count: Int) -> [UnitRect?] {
        guard count > 0 else { return [] }
        var frames: [UnitRect?] = Array(repeating: nil, count: count)
        switch self {
        case .fullscreen:
            frames[0] = .full
        case .pictureInPicture:
            frames[0] = .full
            if count > 1 { frames[1] = UnitRect(x: 0.68, y: 0.05, width: 0.28, height: 0.28) }
            if count > 2 { frames[2] = UnitRect(x: 0.04, y: 0.05, width: 0.28, height: 0.28) }
        case .splitHorizontal:
            frames[0] = UnitRect(x: 0, y: 0, width: 0.5, height: 1)
            if count > 1 { frames[1] = UnitRect(x: 0.5, y: 0, width: 0.5, height: 1) }
        case .splitVertical:
            frames[0] = UnitRect(x: 0, y: 0, width: 1, height: 0.5)
            if count > 1 { frames[1] = UnitRect(x: 0, y: 0.5, width: 1, height: 0.5) }
        case .quad:
            let cells = [
                UnitRect(x: 0, y: 0, width: 0.5, height: 0.5), UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                UnitRect(x: 0, y: 0.5, width: 0.5, height: 0.5), UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
            for index in 0..<min(count, 4) { frames[index] = cells[index] }
        }
        return frames
    }

    /// The overrides this layout implies for the given video objects (in draw order, top-most
    /// last). The first object listed is treated as the main camera.
    public func overrides(for videoObjects: [DisplayObjectID]) -> [DisplayObjectID: ObjectOverride] {
        var result: [DisplayObjectID: ObjectOverride] = [:]
        for (id, frame) in zip(videoObjects, frames(count: videoObjects.count)) {
            result[id] = frame.map { ObjectOverride(isVisible: true, frame: $0) } ?? ObjectOverride(isVisible: false)
        }
        return result
    }
}
