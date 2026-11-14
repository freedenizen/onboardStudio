import Foundation

/// The measures of a performance run (#553), with the names a driver reads them by.
extension PerformanceRuns {
    /// A speed range timed from a standing start, or between two speeds.
    public enum SpeedRange: String, CaseIterable, Codable, Sendable {
        case zeroToThirtyMph, zeroToSixtyMph, zeroToHundredMph, sixtyToHundredThirtyMph
        case zeroToFiftyKmh, zeroToHundredKmh, zeroToTwoHundredKmh, hundredToTwoHundredKmh

        static let mph = 0.447_04
        static let kmh = 1 / 3.6

        /// From and to, in m/s.
        public var speeds: (from: Double, to: Double) {
            switch self {
            case .zeroToThirtyMph: (0, 30 * Self.mph)
            case .zeroToSixtyMph: (0, 60 * Self.mph)
            case .zeroToHundredMph: (0, 100 * Self.mph)
            case .sixtyToHundredThirtyMph: (60 * Self.mph, 130 * Self.mph)
            case .zeroToFiftyKmh: (0, 50 * Self.kmh)
            case .zeroToHundredKmh: (0, 100 * Self.kmh)
            case .zeroToTwoHundredKmh: (0, 200 * Self.kmh)
            case .hundredToTwoHundredKmh: (100 * Self.kmh, 200 * Self.kmh)
            }
        }

        /// The ones shown to a driver who reads km/h; the others are for mph.
        public var isMetric: Bool {
            switch self {
            case .zeroToFiftyKmh, .zeroToHundredKmh, .zeroToTwoHundredKmh, .hundredToTwoHundredKmh: true
            default: false
            }
        }

        /// "0–60 mph", "100–200 km/h".
        public var label: String {
            switch self {
            case .zeroToThirtyMph: "0–30 mph"
            case .zeroToSixtyMph: "0–60 mph"
            case .zeroToHundredMph: "0–100 mph"
            case .sixtyToHundredThirtyMph: "60–130 mph"
            case .zeroToFiftyKmh: "0–50 km/h"
            case .zeroToHundredKmh: "0–100 km/h"
            case .zeroToTwoHundredKmh: "0–200 km/h"
            case .hundredToTwoHundredKmh: "100–200 km/h"
            }
        }
    }

    /// A drag strip's marks: the same distances whatever unit a driver reads; only the names
    /// change.
    public enum DragDistance: String, CaseIterable, Codable, Sendable {
        case sixtyFeet, threeHundredThirtyFeet, eighthMile, thousandFeet, quarterMile

        public var metres: Double {
            switch self {
            case .sixtyFeet: 60 * 0.3048
            case .threeHundredThirtyFeet: 330 * 0.3048
            case .eighthMile: 660 * 0.3048
            case .thousandFeet: 1000 * 0.3048
            case .quarterMile: 1320 * 0.3048
            }
        }

        /// Where a strip has a trap: the eighth and the quarter.
        public var hasTrap: Bool { self == .eighthMile || self == .quarterMile }

        /// "60 ft", "¼ mile" — or "18 m", "402 m" for a driver who reads km/h.
        public func label(metric: Bool) -> String {
            if metric { return "\(Int(metres.rounded())) m" }
            switch self {
            case .sixtyFeet: return "60 ft"
            case .threeHundredThirtyFeet: return "330 ft"
            case .eighthMile: return "⅛ mile"
            case .thousandFeet: return "1,000 ft"
            case .quarterMile: return "¼ mile"
            }
        }
    }

    /// The speed a stop is timed from.
    public enum BrakingSpeed: String, CaseIterable, Codable, Sendable {
        case sixtyMph, hundredKmh

        public var metresPerSecond: Double { self == .sixtyMph ? 60 * SpeedRange.mph : 100 * SpeedRange.kmh }
        public var isMetric: Bool { self == .hundredKmh }
        public var label: String { self == .sixtyMph ? "60–0 mph" : "100–0 km/h" }
    }
}
