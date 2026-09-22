/// The dimension a unit measures, and so the set of units a value in it can be shown in.
///
/// A value only ever converts within its own family: kPa becomes bar, never mph. Pickers offering
/// the user a display unit read `TelemetryUnit.convertibleUnits` rather than the whole enum, so
/// nobody is offered bar for throttle (#89).
public enum UnitFamily: String, Hashable, Sendable, CaseIterable {
    case time
    case length
    case angle
    case speed
    case acceleration
    case rotation
    case ratio
    case temperature
    case pressure

    /// The unit every member converts through. Arbitrary but fixed: the conversion table below is
    /// written once per unit against this, instead of once per ordered pair.
    public var base: TelemetryUnit {
        switch self {
        case .time: .seconds
        case .length: .meters
        case .angle: .degrees
        case .speed: .metersPerSecond
        case .acceleration: .gForce
        case .rotation: .rpm
        case .ratio: .percent
        case .temperature: .celsius
        case .pressure: .kilopascal
        }
    }

    /// Every unit in the family, in the order a picker should offer them.
    public var units: [TelemetryUnit] {
        switch self {
        case .time: [.seconds]
        case .length: [.meters, .kilometers, .feet, .miles]
        case .angle: [.degrees]
        case .speed: [.metersPerSecond, .kilometersPerHour, .milesPerHour]
        case .acceleration: [.gForce]
        case .rotation: [.rpm]
        case .ratio: [.percent]
        case .temperature: [.celsius, .fahrenheit]
        case .pressure: [.kilopascal, .bar, .psi]
        }
    }
}

/// Physical unit of a channel's values. Values are stored in the unit the file provided;
/// `canonical` conversions normalise to SI-style units used internally by renderers.
public enum TelemetryUnit: Hashable, Sendable, Codable {
    case none
    case seconds
    case meters
    case feet
    case kilometers
    case miles
    case degrees
    case metersPerSecond
    case kilometersPerHour
    case milesPerHour
    case gForce
    case rpm
    case percent
    case count
    case celsius
    case fahrenheit
    case kilopascal
    case bar
    case psi
    case custom(String)

    /// Short display symbol, e.g. `m/s`, `km/h`, `°`.
    public var symbol: String {
        switch self {
        case .none: ""
        case .seconds: "s"
        case .meters: "m"
        case .feet: "ft"
        case .kilometers: "km"
        case .miles: "mi"
        case .degrees: "°"
        case .metersPerSecond: "m/s"
        case .kilometersPerHour: "km/h"
        case .milesPerHour: "mph"
        case .gForce: "G"
        case .rpm: "rpm"
        case .percent: "%"
        case .count: ""
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .kilopascal: "kPa"
        case .bar: "bar"
        case .psi: "psi"
        case .custom(let symbol): symbol
        }
    }

    /// Parses common unit spellings found in data-logger headers (`km/h`, `kph`, `mph`, `G`, …).
    public init(parsing text: String) {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "": self = .none
        case "s", "sec", "seconds": self = .seconds
        case "m", "meters", "metres": self = .meters
        case "ft", "feet": self = .feet
        case "km": self = .kilometers
        case "mi", "miles": self = .miles
        case "deg", "degrees", "°": self = .degrees
        case "m/s", "mps": self = .metersPerSecond
        case "km/h", "kph", "kmh": self = .kilometersPerHour
        case "mph", "mi/h": self = .milesPerHour
        case "g", "gs": self = .gForce
        case "rpm": self = .rpm
        case "%", "percent": self = .percent
        case "c", "°c", "celsius": self = .celsius
        case "f", "°f", "fahrenheit": self = .fahrenheit
        case "kpa": self = .kilopascal
        case "bar", "bars": self = .bar
        case "psi": self = .psi
        default: self = .custom(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The unit renderers expect for a given role, or `nil` when any unit is acceptable.
    public static func canonical(for role: ChannelRole) -> TelemetryUnit? {
        switch role {
        case .time: .seconds
        case .speed: .metersPerSecond
        case .altitude, .distance, .accuracy: .meters
        case .heading, .latitude, .longitude: .degrees
        case .longitudinalG, .lateralG: .gForce
        case .rpm: .rpm
        case .throttle, .brake: .percent
        default: nil
        }
    }

    /// What this unit measures, or `nil` for the units that measure nothing in particular —
    /// `none`, `count` and anything the importer could only take verbatim as `custom`.
    public var family: UnitFamily? {
        switch self {
        case .seconds: .time
        case .meters, .feet, .kilometers, .miles: .length
        case .degrees: .angle
        case .metersPerSecond, .kilometersPerHour, .milesPerHour: .speed
        case .gForce: .acceleration
        case .rpm: .rotation
        case .percent: .ratio
        case .celsius, .fahrenheit: .temperature
        case .kilopascal, .bar, .psi: .pressure
        case .none, .count, .custom: nil
        }
    }

    /// Every unit a value in this one can be shown in, including itself. Empty when the unit has
    /// no family, which is the honest answer: nothing is known about what it measures.
    public var convertibleUnits: [TelemetryUnit] { family?.units ?? [] }

    /// Scale and offset taking a value in `self` to its family's base unit: `base = value * scale
    /// + offset`. Offsets exist because temperature scales do not share a zero — °C and °F is the
    /// one pair here that a bare multiplier cannot express.
    private var toBase: (scale: Double, offset: Double)? {
        switch self {
        case .seconds, .meters, .degrees, .metersPerSecond, .gForce, .rpm, .percent, .celsius, .kilopascal:
            (1, 0)
        case .feet: (0.3048, 0)
        case .kilometers: (1000, 0)
        case .miles: (1609.344, 0)
        case .kilometersPerHour: (1 / 3.6, 0)
        case .milesPerHour: (0.44704, 0)
        case .fahrenheit: (5 / 9, -160 / 9)
        case .bar: (100, 0)
        case .psi: (6.894_757, 0)
        case .none, .count, .custom: nil
        }
    }

    /// Converts one value from `self` to `target`, or `nil` if the units are not dimensionally
    /// compatible. Handles offsets, so this — not `conversionFactor(to:)` — is what temperature
    /// must go through.
    public func convert(_ value: Double, to target: TelemetryUnit) -> Double? {
        if self == target { return value }
        guard let from = toBase, let into = target.toBase, family == target.family else { return nil }
        return (value * from.scale + from.offset - into.offset) / into.scale
    }

    /// Multiplier that converts a value in `self` to `target`, or `nil` if the units are not
    /// dimensionally compatible **or the conversion has an offset**. Scaling by a factor is wrong
    /// for °C ↔ °F, so this answers `nil` there rather than a number that is close enough to look
    /// right; callers that must handle every family use `convert(_:to:)`.
    public func conversionFactor(to target: TelemetryUnit) -> Double? {
        if self == target { return 1 }
        guard let from = toBase, let into = target.toBase, family == target.family,
            from.offset == into.offset
        else { return nil }
        return from.scale / into.scale
    }
}
