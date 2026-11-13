import Foundation

/// A place on the ground, degrees.
public struct GeoPoint: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A name a circuit gives one of its turns, pinned to where the turn is (#548).
///
/// Names used to be a list in driving order, given to the corners found by position in it. The
/// detector does not find the same corners on every lap — a kink near the line is a corner on one
/// lap and not the next — and one corner more moved every name after it one turn along. A name
/// pinned to the apex stays on its turn whatever else a lap finds.
public struct TurnName: Hashable, Codable, Sendable {
    /// What the circuit calls it: "3a", "Carousel". Never empty — an unnamed turn is not pinned.
    public var label: String
    /// The apex, degrees.
    public var latitude: Double
    public var longitude: Double
    /// The bend from entry to exit (`Corner.trace`) on the lap it was named on; empty when only
    /// the apex is known.
    public var trace: [GeoPoint]

    public init(label: String, latitude: Double, longitude: Double, trace: [GeoPoint] = []) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.trace = trace
    }

    /// A name pinned to `corner`, or `nil` for a corner placed by distance alone.
    public init?(label: String, corner: Corner) {
        guard let latitude = corner.apexLatitude, let longitude = corner.apexLongitude else { return nil }
        self.init(label: label, latitude: latitude, longitude: longitude, trace: corner.trace)
    }

    private enum CodingKeys: String, CodingKey { case label, latitude, longitude, trace }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        trace = try c.decodeIfPresent([GeoPoint].self, forKey: .trace) ?? []
    }
}

/// What one corner is called, and where the name came from.
public struct CornerName: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// A name the driver gave: pinned to this turn, or, in a project from before names were
        /// pinned, the name at this corner's place in the list.
        case named
        /// A corner the driver has not named while naming others: called by the named turns either
        /// side of it, "3a–4", which stays the same on every lap that finds it.
        case between
        /// Nothing is named, so the corner's place in the lap: a count, not the circuit's number.
        case counted
    }

    public var label: String
    public var source: Source

    public init(label: String, source: Source) {
        self.label = label
        self.source = source
    }
}

/// Gives the corners a lap found the names the driver pinned to the circuit (#548).
public enum CornerNaming {
    /// How far a corner may be from a pinned name and still take it, metres: from the lap's apex
    /// to the named bend, or from the named apex to the lap's bend, whichever is nearer.
    ///
    /// Measured against the bend rather than the apex alone because the apex of a long
    /// constant-radius bend moves along it by more than this from lap to lap. Each name goes to
    /// the nearest corner first, so two turns closer than this still each keep their own.
    public static let matchRadiusMeters = 40.0

    /// How much the distance between apexes counts against a pairing, beside the distance to the
    /// bend: enough to break a tie between two corners on one bend, too little to outweigh a
    /// corner that lies on the bend against one that does not.
    static let apexWeight = 0.25

    /// How far `corner` is from `pin`, metres; `nil` for a corner placed by distance alone.
    public static func distance(from corner: Corner, to pin: TurnName) -> Double? {
        guard let latitude = corner.apexLatitude, let longitude = corner.apexLongitude else { return nil }
        func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
            DerivedChannels.distance(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        }
        var nearest = metres(latitude, longitude, pin.latitude, pin.longitude)
        for point in pin.trace {
            nearest = min(nearest, metres(latitude, longitude, point.latitude, point.longitude))
        }
        for point in corner.trace {
            nearest = min(nearest, metres(point.latitude, point.longitude, pin.latitude, pin.longitude))
        }
        return nearest
    }

    /// The name of every corner in `corners`, in the same order.
    ///
    /// With nothing pinned, `legacy` is read as it always was — the `index`-th name for the
    /// `index`-th corner, blanks and the rest counted — so a project saved before names were
    /// pinned draws the same numbers it always did.
    public static func names(for corners: [Corner], pinned: [TurnName], legacy: [String] = []) -> [CornerName] {
        guard !pinned.isEmpty else {
            return corners.indices.map { index in
                index < legacy.count && !legacy[index].isEmpty
                    ? CornerName(label: legacy[index], source: .named)
                    : CornerName(label: "\(index + 1)", source: .counted)
            }
        }
        let matched = match(corners, to: pinned)
        let named = corners.indices.compactMap { index in matched[index].map { (index, pinned[$0].label) } }
        guard !named.isEmpty else {
            return corners.indices.map { CornerName(label: "\($0 + 1)", source: .counted) }
        }
        return corners.indices.map { index in
            if let pin = matched[index] { return CornerName(label: pinned[pin].label, source: .named) }
            // A lap goes round, so the turn before the first named one is the last named one.
            let before = named.last { $0.0 < index } ?? named[named.count - 1]
            let after = named.first { $0.0 > index } ?? named[0]
            return CornerName(label: "\(before.1)–\(after.1)", source: .between)
        }
    }

    /// For each corner, the index into `pinned` of the name it takes, if any.
    ///
    /// Closest pairs first, each corner and each name used once: a corner sitting between two
    /// pinned turns takes the nearer, and the farther goes to its own corner if the lap found one.
    /// Closeness is to the bend, with the distance between apexes breaking ties.
    public static func match(_ corners: [Corner], to pinned: [TurnName]) -> [Int?] {
        struct Pair {
            let corner: Int
            let pin: Int
            let metres: Double
        }
        var pairs: [Pair] = []
        for (cornerIndex, corner) in corners.enumerated() {
            guard let latitude = corner.apexLatitude, let longitude = corner.apexLongitude else { continue }
            for (pinIndex, pin) in pinned.enumerated() {
                guard let metres = distance(from: corner, to: pin), metres <= matchRadiusMeters else { continue }
                // Two corners can both lie on one long named bend — a kink at its entry and the
                // turn itself — so of those the one whose apex is nearer the named apex is first.
                let apart = DerivedChannels.distance(
                    lat1: latitude, lon1: longitude, lat2: pin.latitude, lon2: pin.longitude)
                pairs.append(Pair(corner: cornerIndex, pin: pinIndex, metres: metres + apart * apexWeight))
            }
        }
        pairs.sort { $0.metres < $1.metres }
        var result = [Int?](repeating: nil, count: corners.count)
        var usedPins = Set<Int>()
        for pair in pairs where result[pair.corner] == nil && !usedPins.contains(pair.pin) {
            result[pair.corner] = pair.pin
            usedPins.insert(pair.pin)
        }
        return result
    }

    /// `pinned` with the corner at `index` called `label`, or unnamed when `label` is blank.
    ///
    /// The first name given pins every corner the lap found with the name it shows now — the
    /// list's name or its count — so naming one turn does not leave the others to be called by
    /// their neighbours. Names pinned to turns this lap did not find are kept: they were set on
    /// another lap, and that lap will find them again.
    public static func renaming(
        _ index: Int, to label: String, corners: [Corner], pinned: [TurnName], legacy: [String] = []
    ) -> [TurnName] {
        guard corners.indices.contains(index), corners[index].apexLatitude != nil else { return pinned }
        var result = pinned
        if result.isEmpty {
            result = zip(corners, names(for: corners, pinned: [], legacy: legacy)).compactMap { corner, name in
                TurnName(label: name.label, corner: corner)
            }
        }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pin = match(corners, to: result)[index] {
            if trimmed.isEmpty {
                result.remove(at: pin)
            } else {
                result[pin].label = trimmed
            }
        } else if !trimmed.isEmpty, let pin = TurnName(label: trimmed, corner: corners[index]) {
            result.append(pin)
        }
        return result
    }
}

extension TelemetrySession {
    /// What each of `corners` is called at this circuit: the pinned names, else the list a
    /// project from before names were pinned keeps, else their count (#548).
    public func cornerNames(for corners: [Corner]) -> [CornerName] {
        CornerNaming.names(for: corners, pinned: turnNames, legacy: cornerLabels)
    }
}
