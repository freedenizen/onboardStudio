import Foundation
import TelemetryKit

/// How performance runs (#553) read, the same in the Logbook and on a Stat Card: the measures a
/// driver who reads mph is shown, or km/h, and their numbers in words.
public enum PerformanceWording {
    /// The speed ranges for a driver who reads km/h (`metric`), or mph.
    public static func speedRanges(metric: Bool) -> [PerformanceRuns.SpeedRange] {
        PerformanceRuns.SpeedRange.allCases.filter { $0.isMetric == metric }
    }

    /// 0–100 km/h, or 0–60 mph: the launch everybody quotes.
    public static func launch(metric: Bool) -> PerformanceRuns.SpeedRange {
        metric ? .zeroToHundredKmh : .zeroToSixtyMph
    }

    /// 100–0 km/h, or 60–0 mph.
    public static func braking(metric: Bool) -> PerformanceRuns.BrakingSpeed {
        metric ? .hundredKmh : .sixtyMph
    }

    /// How the distance times are timed, said wherever they are shown.
    public static let rollout = "1-ft rollout, as a timeslip"

    /// "5.36 s".
    public static func seconds(_ seconds: Double) -> String { String(format: "%.2f s", seconds) }

    /// "86 mph", "138 km/h".
    public static func speed(_ metresPerSecond: Double, metric: Bool) -> String {
        let unit: SpeedDisplayUnit = metric ? .kph : .mph
        return "\(Int((metresPerSecond * unit.factorFromMetersPerSecond).rounded())) \(metric ? "km/h" : "mph")"
    }

    /// "36.2 m", "119 ft".
    public static func distance(_ metres: Double, metric: Bool) -> String {
        metric ? String(format: "%.1f m", metres) : "\(Int((metres / 0.3048).rounded())) ft"
    }

    /// "12.84 s @ 108 mph": a mark's time and, where the strip has a trap, its trap speed.
    public static func mark(_ seconds: Double, trap: Double?, metric: Bool) -> String {
        guard let trap else { return Self.seconds(seconds) }
        return "\(Self.seconds(seconds)) @ \(speed(trap, metric: metric))"
    }
}
