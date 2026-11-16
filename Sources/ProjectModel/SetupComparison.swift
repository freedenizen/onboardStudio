import Foundation
import TelemetryKit

/// What Trends' Before and After splits a circuit's sessions by (#559): the tyre set, the setup's
/// name, the surface, the weather, or any one value of the setup sheet.
public enum SetupSplit: Hashable, Sendable {
    case tyres
    case setup
    case surface
    case weather
    case item(SetupItem)

    public var title: String {
        switch self {
        case .tyres: "Tyres"
        case .setup: "Setup"
        case .surface: "Surface"
        case .weather: "Weather"
        case .item(let item): item.title
        }
    }

    /// What two sessions are compared by; `nil` when the session did not note it.
    public func key(of entry: LogbookEntry) -> String? {
        let conditions = entry.conditions
        switch self {
        case .tyres: return Self.words(conditions.tyres)
        case .setup: return Self.words(conditions.sheet.name)
        case .surface: return conditions.track?.rawValue
        case .weather: return conditions.weather?.rawValue
        case .item(let item): return item.key(in: conditions.sheet)
        }
    }

    /// How the value reads: "RE-71RS", "Wet", "30 psi".
    public func label(of entry: LogbookEntry, units: SetupUnits) -> String? {
        let conditions = entry.conditions
        switch self {
        case .tyres:
            return Self.words(conditions.tyres).map { _ in conditions.tyres.trimmingCharacters(in: .whitespaces) }
        case .setup: return Self.words(conditions.sheet.name).map { _ in conditions.sheet.name }
        case .surface: return conditions.track?.displayName
        case .weather: return conditions.weather?.displayName
        case .item(let item): return item.text(in: conditions.sheet, units: units)
        }
    }

    private static func words(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Every split, in the order Trends offers them.
    public static let all: [SetupSplit] = [.tyres, .setup, .surface, .weather] + SetupItem.all.map(SetupSplit.item)
}

/// Did a change help (#559): two groups of a circuit's sessions, one value of a split each, read
/// across the whole lap, every sector and every corner — a gain in one corner is often lost in
/// another, so the lap time alone does not say what the change did.
public struct SetupComparison: Sendable {
    /// One side: the sessions that noted one value.
    public struct Group: Sendable {
        public var key: String
        public var label: String
        public var entryIDs: [UUID]
        /// The quickest lap of any of them.
        public var best: Double?
        /// Each session's best, averaged: what a change does to a session, not to one lucky lap.
        public var averageBest: Double?
        public var optimal: Double?
        /// The sessions' lap spreads, averaged.
        public var spread: Double?
        /// The quickest time through each sector, in the circuit's sectors.
        public var sectors: [Double?]
        /// Each corner's minimum speed and time, averaged over the sessions' best laps, by label.
        public var corners: [String: Corner]

        public var sessions: Int { entryIDs.count }
    }

    public struct Corner: Sendable, Hashable {
        /// m/s.
        public var minimumSpeed: Double
        public var timeInCorner: Double
    }

    /// B against A at one corner: positive speed is faster through it, negative time quicker.
    public struct CornerDifference: Sendable, Hashable {
        public var label: String
        public var minimumSpeed: Double
        public var time: Double
    }

    public var split: SetupSplit
    public var before: Group
    public var after: Group

    /// After's average best less before's: negative is quicker.
    public var averageBestDifference: Double? {
        guard let a = before.averageBest, let b = after.averageBest else { return nil }
        return b - a
    }

    /// After's quickest sector less before's, sector by sector; empty when the sessions were not cut
    /// into the same sectors.
    public var sectorDifferences: [Double?] {
        guard before.sectors.count == after.sectors.count else { return [] }
        return zip(before.sectors, after.sectors).map { a, b in
            guard let a, let b else { return nil }
            return b - a
        }
    }

    /// Every corner both sides drove, in the order of the lap.
    public var cornerDifferences: [CornerDifference] {
        cornerOrder.compactMap { label in
            guard let a = before.corners[label], let b = after.corners[label] else { return nil }
            return CornerDifference(
                label: label, minimumSpeed: b.minimumSpeed - a.minimumSpeed, time: b.timeInCorner - a.timeInCorner)
        }
    }

    /// The corners in lap order, from the sessions that read them.
    public var cornerOrder: [String]

    /// Reasons the difference may not be the change: too few sessions, or every session of one side
    /// in other conditions.
    public var caveats: [String]
}

extension SetupComparison {
    /// The splits two or more of `entries` differ by, in the order Trends offers them.
    public static func splits(in entries: [LogbookEntry]) -> [SetupSplit] {
        SetupSplit.all.filter { split in Set(entries.compactMap(split.key)).count >= 2 }
    }

    /// The values of `split` among `entries`, as (key, label), in the order they were first driven.
    public static func values(of split: SetupSplit, in entries: [LogbookEntry], units: SetupUnits) -> [(
        key: String, label: String
    )] {
        var seen: [(key: String, label: String)] = []
        for entry in entries.sorted(by: { ($0.date ?? $0.added) < ($1.date ?? $1.added) }) {
            guard let key = split.key(of: entry), let label = split.label(of: entry, units: units),
                !seen.contains(where: { $0.key == key })
            else { continue }
            seen.append((key, label))
        }
        return seen
    }

    /// `entries` that noted `before` against those that noted `after`; `nil` when either has none.
    public static func compare(
        _ split: SetupSplit, before: String, after: String, in entries: [LogbookEntry], units: SetupUnits
    ) -> SetupComparison? {
        let sideA = entries.filter { split.key(of: $0) == before }
        let sideB = entries.filter { split.key(of: $0) == after }
        guard !sideA.isEmpty, !sideB.isEmpty, before != after else { return nil }
        // Sectors compare only when every session was cut into the same number of them.
        let counts = Set((sideA + sideB).map(sectorCount))
        let sectors = counts.count == 1 ? counts.first ?? 0 : 0
        let order = (sideA + sideB).max { $0.corners.count < $1.corners.count }?.corners.map(\.label) ?? []
        var comparison = SetupComparison(
            split: split, before: group(sideA, key: before, split: split, sectors: sectors, units: units),
            after: group(sideB, key: after, split: split, sectors: sectors, units: units), cornerOrder: order,
            caveats: [])
        comparison.caveats = caveats(split, sideA, sideB)
        return comparison
    }

    static func sectorCount(_ entry: LogbookEntry) -> Int {
        entry.laps.filter { $0.isComplete && $0.counts }.map(\.sectors.count).max() ?? 0
    }

    static func group(
        _ entries: [LogbookEntry], key: String, split: SetupSplit, sectors: Int, units: SetupUnits
    ) -> Group {
        let bests = entries.compactMap(\.bestLap)
        let spreads = entries.compactMap { LogbookTrends.lapSpread(of: $0) }
        let laps = entries.flatMap(\.laps).filter { $0.isComplete && $0.counts }
        let sectorBests: [Double?] = (0..<sectors).map { index in
            laps.compactMap { index < $0.sectors.count ? $0.sectors[index] : nil }.min()
        }
        var corners: [String: [CornerRecord]] = [:]
        for record in entries.flatMap(\.corners) { corners[record.label, default: []].append(record) }
        return Group(
            key: key, label: entries.lazy.compactMap { split.label(of: $0, units: units) }.first ?? key,
            entryIDs: entries.map(\.id), best: bests.min(), averageBest: mean(bests),
            optimal: entries.compactMap(\.optimalLap).min(), spread: mean(spreads), sectors: sectorBests,
            corners: corners.mapValues { records in
                Corner(
                    minimumSpeed: mean(records.map(\.minimumSpeed)) ?? 0,
                    timeInCorner: mean(records.map(\.timeInCorner)) ?? 0)
            })
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// One session a side, or every session of one side on another surface, tyre set or in other
    /// weather from every one of the other.
    static func caveats(_ split: SetupSplit, _ sideA: [LogbookEntry], _ sideB: [LogbookEntry]) -> [String] {
        var said: [String] = []
        if sideA.count == 1 || sideB.count == 1 {
            said.append("One session on a side: a difference this size may be the day, not the change.")
        }
        for other in [SetupSplit.surface, .weather, .tyres] where other != split {
            let a = Set(sideA.compactMap(other.key))
            let b = Set(sideB.compactMap(other.key))
            guard !a.isEmpty, !b.isEmpty, a.isDisjoint(with: b) else { continue }
            let units = SetupUnits.following(imperial: false)
            let before = sideA.compactMap { other.label(of: $0, units: units) }.first ?? ""
            let after = sideB.compactMap { other.label(of: $0, units: units) }.first ?? ""
            said.append(
                "The \(other.title.lowercased()) differed too (\(before) against \(after)): "
                    + "the difference may be that, not the change.")
        }
        return said
    }
}

extension SetupComparison {
    /// "28 psi: each session's best averaged 0.42 s quicker than 30 psi (3 sessions against 4)."
    public var headline: String {
        let count = "\(after.sessions) session\(after.sessions == 1 ? "" : "s") against \(before.sessions)"
        guard let difference = averageBestDifference else {
            return "\(after.label) against \(before.label): no lap times to compare (\(count))."
        }
        let how =
            difference.magnitude < 0.005
            ? "the same as"
            : String(format: "%.2f s %@ than", difference.magnitude, difference < 0 ? "quicker" : "slower")
        return "\(after.label): each session's best averaged \(how) \(before.label) (\(count))."
    }

    /// "Quicker in sectors 1 and 3; slower in sector 2." Within `tolerance` seconds is neither.
    public func sectorSentence(tolerance: Double = 0.02) -> String? {
        let differences = sectorDifferences.enumerated().compactMap { index, value in value.map { (index + 1, $0) } }
        let quicker = differences.filter { $0.1 < -tolerance }.map { String($0.0) }
        let slower = differences.filter { $0.1 > tolerance }.map { String($0.0) }
        return Self.sentence(quicker: quicker, slower: slower, noun: ("sector", "sectors"), preposition: "in")
    }

    /// "Quicker through Turn 4 and Turn 7; slower through Turn 2."
    public func cornerSentence(tolerance: Double = 0.02) -> String? {
        let differences = cornerDifferences
        let quicker = differences.filter { $0.time < -tolerance }.map(\.label)
        let slower = differences.filter { $0.time > tolerance }.map(\.label)
        return Self.sentence(quicker: quicker, slower: slower, noun: ("", ""), preposition: "through")
    }

    static func sentence(quicker: [String], slower: [String], noun: (String, String), preposition: String) -> String? {
        func part(_ word: String, _ names: [String]) -> String? {
            guard !names.isEmpty else { return nil }
            let kind = noun.0.isEmpty ? "" : (names.count == 1 ? noun.0 : noun.1) + " "
            return "\(word) \(preposition) \(kind)\(names.formattedList)"
        }
        let parts = [part("quicker", quicker), part("slower", slower)].compactMap { $0 }
        guard let first = parts.first else { return nil }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: "; ") + "."
    }
}
