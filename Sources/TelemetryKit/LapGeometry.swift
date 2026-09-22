import Foundation

/// A gate across the track, as a logger records one: two points rather than a point and a
/// direction (#71).
///
/// Racelogic's `[laptiming]` section is the only place in any format surveyed where start/finish
/// and sector geometry is stored at all — every other format carries lap *times*, or a single
/// point at best. Circuit Tools and Harry's LapTimer both read and write it, which makes it the
/// nearest thing to an interchange format for where a lap begins.
public struct LapGate: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// Where a lap begins and ends.
        case start
        /// A sector boundary, in the order the track runs them.
        case split
        /// The end of a point-to-point run, which is not where it began.
        case finish
    }

    public var kind: Kind
    /// What the logger called it — "Start / Finish", "Split 1". Empty when it named it nothing.
    public var label: String
    public var startLatitude: Double
    public var startLongitude: Double
    public var endLatitude: Double
    public var endLongitude: Double

    public init(
        kind: Kind, label: String = "", startLatitude: Double, startLongitude: Double,
        endLatitude: Double, endLongitude: Double
    ) {
        self.kind = kind
        self.label = label
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
    }

    public var centreLatitude: Double { (startLatitude + endLatitude) / 2 }
    public var centreLongitude: Double { (startLongitude + endLongitude) / 2 }

    /// How far the gate reaches either side of its centre, which is what the lap detector wants.
    /// Taken from the gate itself rather than assumed: a logger draws a line as wide as the track
    /// is, and that is better information than any default.
    public var halfWidthMeters: Double {
        let metresPerDegree = 111_320.0
        let latitudeSpan = (endLatitude - startLatitude) * metresPerDegree
        let longitudeSpan =
            (endLongitude - startLongitude) * metresPerDegree * cos(centreLatitude * .pi / 180)
        return max(1, (latitudeSpan * latitudeSpan + longitudeSpan * longitudeSpan).squareRoot() / 2)
    }
}

/// The gates a file carried, in the order it listed them.
///
/// Deliberately not turned into a `FinishLine` here. A gate says where a lap begins and how wide
/// the line is; it says nothing about which way the car crosses it, and the two perpendiculars are
/// equally consistent with the geometry. Inventing a direction would narrow the detector to a
/// guess, so the heading is left unset and any direction accepted.
public struct LapGeometry: Sendable, Hashable {
    public var gates: [LapGate]

    public init(gates: [LapGate] = []) {
        self.gates = gates
    }

    public var isEmpty: Bool { gates.isEmpty }
    public var start: LapGate? { gates.first { $0.kind == .start } }
    /// Sector boundaries in the order the track runs them. The start/finish is not one of them.
    public var splits: [LapGate] { gates.filter { $0.kind == .split } }
}
