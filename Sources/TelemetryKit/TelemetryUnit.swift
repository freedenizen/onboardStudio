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

    /// Multiplier that converts a value in `self` to `target`, or `nil` if the units are not
    /// dimensionally compatible.
    public func conversionFactor(to target: TelemetryUnit) -> Double? {
        if self == target { return 1 }
        switch (self, target) {
        case (.kilometersPerHour, .metersPerSecond): return 1 / 3.6
        case (.milesPerHour, .metersPerSecond): return 0.44704
        case (.metersPerSecond, .kilometersPerHour): return 3.6
        case (.metersPerSecond, .milesPerHour): return 1 / 0.44704
        case (.kilometersPerHour, .milesPerHour): return 0.621_371_192
        case (.milesPerHour, .kilometersPerHour): return 1.609_344
        case (.feet, .meters): return 0.3048
        case (.meters, .feet): return 1 / 0.3048
        case (.kilometers, .meters): return 1000
        case (.meters, .kilometers): return 0.001
        case (.miles, .meters): return 1609.344
        case (.meters, .miles): return 1 / 1609.344
        case (.psi, .kilopascal): return 6.894_757
        case (.kilopascal, .psi): return 1 / 6.894_757
        default: return nil
        }
    }
}
