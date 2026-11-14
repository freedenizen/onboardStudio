import Foundation
import TelemetryKit

/// A circuit's configurations (#549): the long course and the club course, with and without the
/// chicane. They share some corners and not others, number their turns differently and usually
/// start and finish in different places, so a lap of one says nothing about a lap of the other.
///
/// A configuration is part of the key everything about a circuit is kept under — its track
/// definition, its personal best, its Trends, its goals, its plan, its card. The circuit's own key
/// with no configuration is the circuit as it always was, so nothing kept before configurations
/// existed moves: a session, a goal or a definition saved before is the circuit's unnamed
/// configuration, and stays where it was.
public enum CircuitKey {
    /// Between the circuit and the configuration in a key: `Q112563|Club Course`. Never in a
    /// configuration's name (`cleaned` takes it out) nor in a Wikidata id.
    public static let separator: Character = "|"

    /// The key for `configuration` of the circuit keyed `base`; `base` itself with none.
    public static func make(_ base: String, configuration: String?) -> String {
        guard let name = configuration.map(cleaned), !name.isEmpty, !base.isEmpty else { return base }
        return "\(base)\(separator)\(name)"
    }

    /// The circuit's own key, without the configuration.
    public static func base(of key: String) -> String {
        key.firstIndex(of: separator).map { String(key[..<$0]) } ?? key
    }

    /// The configuration in a key; `nil` for the circuit's unnamed configuration.
    public static func configuration(of key: String) -> String? {
        key.firstIndex(of: separator).map { String(key[key.index(after: $0)...]) }
    }

    /// A configuration's name as kept: trimmed, without the separator; empty means none.
    public static func cleaned(_ name: String) -> String {
        name.replacingOccurrences(of: String(separator), with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Sonoma Raceway — Club Course", or the circuit's name alone for its unnamed configuration.
    public static func title(_ circuit: String, configuration: String?) -> String {
        guard let name = configuration.map(cleaned), !name.isEmpty else { return circuit }
        return "\(circuit) — \(name)"
    }
}

extension LogbookFilter {
    /// The configurations named at the circuit keyed `base`, by the logbook's sessions there and by
    /// the definitions kept for it, in alphabetical order; the unnamed one is not among them.
    public static func configurations(
        at base: String, in entries: [LogbookEntry], definitions: [TrackDefinition] = []
    ) -> [String] {
        guard !base.isEmpty else { return [] }
        let named =
            entries.filter { baseCircuitKey(of: $0) == base }.compactMap(\.configuration)
            + definitions.filter { $0.circuitID == base }.compactMap(\.configuration)
        return Array(Set(named.map(CircuitKey.cleaned).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Which configuration of a circuit a session was driven on, read from where its turns are (#549).
public enum ConfigurationMatch {
    /// The share of a configuration's named turns, and of the lap's corners, that must agree before
    /// a session is filed under it. Below this the session stays on the circuit's unnamed
    /// configuration, where it would have gone before configurations existed, for the driver to
    /// move it.
    public static let minimumAgreement = 0.75

    /// The configuration of `definitions` — all of one circuit's — whose named turns the session's
    /// best lap drives through; `nil` for the unnamed configuration or when none is clear.
    ///
    /// Only definitions with named turns can be told apart: two configurations with only a
    /// start/finish line differ in nothing a lap can show.
    public static func configuration(of session: TelemetrySession, among definitions: [TrackDefinition]) -> String? {
        let named = definitions.filter { !$0.turnNames.isEmpty }
        // With nothing to tell apart there is nothing to choose: the unnamed configuration.
        guard named.contains(where: { $0.configuration != nil }),
            let best = LapDeltas.sessionBest(in: session), let profile = LapProfile(lap: best, in: session)
        else { return nil }
        let corners = CornerDetector.corners(of: profile)
        let scored = named.map { definition in
            (definition.configuration, agreement(of: corners, with: definition.turnNames))
        }
        guard let top = scored.max(by: { $0.1 < $1.1 }), top.1 >= minimumAgreement else { return nil }
        // Two configurations that agree equally — every turn of a short layout lies on a longer
        // one — are not a choice the app can make.
        guard scored.filter({ $0.1 == top.1 }).count == 1 else { return nil }
        return top.0
    }

    /// How well a lap's corners and a configuration's named turns agree, 0…1: the turns matched,
    /// out of the more of the two counts, so a configuration whose turns the lap skips and a lap
    /// with corners the configuration lacks both score lower.
    public static func agreement(of corners: [Corner], with turns: [TurnName]) -> Double {
        let total = max(corners.count, turns.count)
        guard total > 0 else { return 0 }
        let matched = CornerNaming.match(corners, to: turns).compactMap { $0 }.count
        return Double(matched) / Double(total)
    }
}
