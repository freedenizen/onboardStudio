import Foundation

/// How a round gauge shows its value.
public enum GaugeStyle: String, Codable, Sendable, CaseIterable {
    /// A single needle.
    case needle
    /// Two needles: the main channel and `secondChannel` (e.g. speed and a target speed).
    case dualNeedle
    /// A filled arc from the minimum to the current value ("graph" style in RaceRender).
    case arc
}

/// Needle proportions, all as fractions of the gauge radius.
public struct NeedleStyle: Hashable, Codable, Sendable {
    /// Distance from the hub to the tip.
    public var length: Double
    /// Distance from the hub to the tail (opposite the tip).
    public var tailLength: Double
    /// Full width at the hub.
    public var width: Double
    public var hubRadius: Double
    /// Whether the needle narrows to a point.
    public var tapered: Bool
    /// Trailing average applied to the value before it moves the needle (0 = none).
    public var smoothingSeconds: Double

    public init(
        length: Double = 0.86,
        tailLength: Double = 0.15,
        width: Double = 0.06,
        hubRadius: Double = 0.08,
        tapered: Bool = true,
        smoothingSeconds: Double = 0
    ) {
        self.length = length
        self.tailLength = tailLength
        self.width = width
        self.hubRadius = hubRadius
        self.tapered = tapered
        self.smoothingSeconds = smoothingSeconds
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NeedleStyle()
        length = try c.decodeIfPresent(Double.self, forKey: .length) ?? defaults.length
        tailLength = try c.decodeIfPresent(Double.self, forKey: .tailLength) ?? defaults.tailLength
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? defaults.width
        hubRadius = try c.decodeIfPresent(Double.self, forKey: .hubRadius) ?? defaults.hubRadius
        tapered = try c.decodeIfPresent(Bool.self, forKey: .tapered) ?? defaults.tapered
        smoothingSeconds = try c.decodeIfPresent(Double.self, forKey: .smoothingSeconds) ?? defaults.smoothingSeconds
    }
}

/// Tick marks and scale labels, lengths as fractions of the radius.
public struct TickStyle: Hashable, Codable, Sendable {
    public var showMajor: Bool
    public var showMinor: Bool
    public var showLabels: Bool
    public var majorLength: Double
    public var minorLength: Double
    /// Radius of the outer end of the ticks.
    public var outerRadius: Double
    /// Radius at which labels are centred.
    public var labelRadius: Double
    public var labelDecimals: Int
    /// Font size of labels as a fraction of the radius.
    public var labelScale: Double
    /// Skip labels that would overlap their neighbours.
    public var declutter: Bool

    public init(
        showMajor: Bool = true,
        showMinor: Bool = true,
        showLabels: Bool = true,
        majorLength: Double = 0.16,
        minorLength: Double = 0.08,
        outerRadius: Double = 0.88,
        labelRadius: Double = 0.58,
        labelDecimals: Int = 0,
        labelScale: Double = 0.13,
        declutter: Bool = true
    ) {
        self.showMajor = showMajor
        self.showMinor = showMinor
        self.showLabels = showLabels
        self.majorLength = majorLength
        self.minorLength = minorLength
        self.outerRadius = outerRadius
        self.labelRadius = labelRadius
        self.labelDecimals = labelDecimals
        self.labelScale = labelScale
        self.declutter = declutter
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TickStyle()
        showMajor = try c.decodeIfPresent(Bool.self, forKey: .showMajor) ?? d.showMajor
        showMinor = try c.decodeIfPresent(Bool.self, forKey: .showMinor) ?? d.showMinor
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? d.showLabels
        majorLength = try c.decodeIfPresent(Double.self, forKey: .majorLength) ?? d.majorLength
        minorLength = try c.decodeIfPresent(Double.self, forKey: .minorLength) ?? d.minorLength
        outerRadius = try c.decodeIfPresent(Double.self, forKey: .outerRadius) ?? d.outerRadius
        labelRadius = try c.decodeIfPresent(Double.self, forKey: .labelRadius) ?? d.labelRadius
        labelDecimals = try c.decodeIfPresent(Int.self, forKey: .labelDecimals) ?? d.labelDecimals
        labelScale = try c.decodeIfPresent(Double.self, forKey: .labelScale) ?? d.labelScale
        declutter = try c.decodeIfPresent(Bool.self, forKey: .declutter) ?? d.declutter
    }
}

/// A value range with a colour: a red zone, a shift light band, an economy band, etc.
public struct GaugeZone: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var from: Double
    /// Upper bound, or `nil` for "to the maximum".
    public var to: Double?
    public var color: RGBAColor

    public init(id: UUID = UUID(), from: Double, to: Double? = nil, color: RGBAColor = .red) {
        self.id = id
        self.from = from
        self.to = to
        self.color = color
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        from = try c.decode(Double.self, forKey: .from)
        to = try c.decodeIfPresent(Double.self, forKey: .to)
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .red
    }
}

/// Which parts of a gauge take on the colour of the zone the value (or tick) falls in.
public struct ZoneTargets: Hashable, Codable, Sendable {
    /// Paint the zone as a band on the face.
    public var face: Bool
    /// Colour tick marks and labels inside a zone.
    public var marks: Bool
    /// Colour the needle (or arc) by the zone the current value is in.
    public var needle: Bool
    /// Blend colours smoothly between thresholds instead of switching at them.
    public var gradient: Bool

    public init(face: Bool = true, marks: Bool = false, needle: Bool = false, gradient: Bool = false) {
        self.face = face
        self.marks = marks
        self.needle = needle
        self.gradient = gradient
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        face = try c.decodeIfPresent(Bool.self, forKey: .face) ?? true
        marks = try c.decodeIfPresent(Bool.self, forKey: .marks) ?? false
        needle = try c.decodeIfPresent(Bool.self, forKey: .needle) ?? false
        gradient = try c.decodeIfPresent(Bool.self, forKey: .gradient) ?? false
    }
}

extension Array where Element == GaugeZone {
    /// The zone containing `value`, if any (later zones win on overlap).
    public func zone(containing value: Double) -> GaugeZone? {
        last { value >= $0.from && value < ($0.to ?? .infinity) }
    }

    /// Zones sorted by their lower bound.
    public var sortedByStart: [GaugeZone] { sorted { $0.from < $1.from } }
}
