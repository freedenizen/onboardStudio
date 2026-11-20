import Foundation
import TelemetryKit

/// The grip a car has shown in conditions like a session's (#558), learned from the logbook: its
/// sessions on the same kind of surface, on the same tyres and in much the same air when those were
/// noted, as a range from the typical session to the best, and the driver's own adjustment of it.
public struct CarGripLimit: Hashable, Sendable {
    /// Each way, the median of the sessions'.
    public var typical: GripEnvelope
    /// Each way, the most any of them reached.
    public var best: GripEnvelope
    public var sessions: Int
    /// What the sessions had in common: "dry", "RE-71RS", "15–25 °C".
    public var basis: [String]
    /// The driver's scale on it, 1 as learned.
    public var adjustment: Double

    /// What grip use is read against: the best the car showed, as the driver has adjusted it.
    public var limit: GripEnvelope { best.scaled(by: adjustment) }

    /// "1.02–1.15 G from 6 sessions, dry, RE-71RS" — the peaks, typical to best.
    public var summary: String {
        let low = typical.scaled(by: adjustment).peak
        let high = limit.peak
        let range = abs(high - low) < 0.005 ? String(format: "%.2f G", high) : String(format: "%.2f–%.2f G", low, high)
        let count = sessions == 1 ? "1 session" : "\(sessions) sessions"
        return ([range + " from " + count] + basis).joined(separator: ", ")
    }
}

public enum CarGrip {
    /// Air temperatures this far apart are much the same.
    public static let temperatureWindow = 8.0

    /// The limit for `entry`'s car in `entry`'s conditions, from `entries`; `nil` when no session in
    /// the car (this one included) showed its grip. With fewer than two sessions alike, the air
    /// and then the tyres are let go; the surface never is, as wet grip says nothing of dry.
    public static func limit(for entry: LogbookEntry, among entries: [LogbookEntry], adjustment: Double = 1)
        -> CarGripLimit?
    {
        let inCar = entries.filter { other in
            other.grip != nil
                && (other.id == entry.id || (!entry.car.isEmpty && Garage.same(other.car, entry.car)))
        }
        let wet = isWet(entry.conditions.track)
        let sameSurface = inCar.filter { isWet($0.conditions.track) == wet || $0.id == entry.id }
        let tyres = entry.conditions.tyres.trimmingCharacters(in: .whitespaces)
        let air = entry.conditions.ambientCelsius
        func sameTyres(_ other: LogbookEntry) -> Bool {
            tyres.isEmpty || other.conditions.tyres.isEmpty || Garage.same(other.conditions.tyres, tyres)
        }
        func sameAir(_ other: LogbookEntry) -> Bool {
            guard let air, let theirs = other.conditions.ambientCelsius else { return true }
            return abs(theirs - air) <= temperatureWindow
        }
        var basis = [wet ? "wet" : "dry"]
        var chosen = sameSurface.filter { sameTyres($0) && sameAir($0) }
        var usedTyres = !tyres.isEmpty
        var usedAir = air != nil
        if chosen.count < 2, usedAir {
            chosen = sameSurface.filter(sameTyres)
            usedAir = false
        }
        if chosen.count < 2, usedTyres {
            chosen = sameSurface
            usedTyres = false
        }
        if usedTyres { basis.append(tyres) }
        if usedAir, let air {
            basis.append(
                "\(Int((air - temperatureWindow).rounded()))–\(Int((air + temperatureWindow).rounded())) °C")
        }
        guard let range = GripEnvelope.range(of: chosen.compactMap { $0.grip?.envelope }) else { return nil }
        return CarGripLimit(
            typical: range.typical, best: range.best, sessions: chosen.count, basis: basis, adjustment: adjustment)
    }

    /// Damp, wet, drying and greasy are all not dry; a surface not noted is taken as dry.
    static func isWet(_ track: SessionConditions.Track?) -> Bool {
        guard let track else { return false }
        return track != .dry
    }
}
