import Foundation

/// A personal best is a question over the logbook (#351): the quickest complete lap at a circuit,
/// in a car, in a year, or ever — and whether a session set one when it was driven.
public struct PersonalBest: Hashable, Sendable {
    public var entryID: UUID
    public var seconds: Double
    public var lapNumber: Int?
    public var date: Date?
    public var car: String

    public init(entryID: UUID, seconds: Double, lapNumber: Int?, date: Date?, car: String) {
        self.entryID = entryID
        self.seconds = seconds
        self.lapNumber = lapNumber
        self.date = date
        self.car = car
    }
}

/// How the Logbook's PB column marks a session that set a personal best (#422).
public enum PersonalBestBadge: Hashable, Sendable {
    /// It holds the personal best at its circuit now, overall or in its car.
    case current
    /// It set one when it was driven, and a later session has beaten it.
    case former
}

public enum PersonalBests {
    /// The best at `circuitKey` (`LogbookFilter.circuitKey`), narrowed to a car and a year when
    /// given; `nil` when no session there has a complete lap.
    public static func best(
        in entries: [LogbookEntry], circuitKey: String, car: String? = nil, year: Int? = nil
    ) -> PersonalBest? {
        // Sessions that name no circuit are not at one place (#455): there is no best among them.
        guard !circuitKey.isEmpty else { return nil }
        let candidates = entries.filter { entry in
            LogbookFilter.circuitKey(of: entry) == circuitKey && entry.bestLap != nil
                && (car.map { entry.car.caseInsensitiveCompare($0) == .orderedSame } ?? true)
                && (year.map { entry.year == $0 } ?? true)
        }
        guard let quickest = candidates.min(by: { ($0.bestLap ?? .infinity) < ($1.bestLap ?? .infinity) }),
            let seconds = quickest.bestLap
        else { return nil }
        return PersonalBest(
            entryID: quickest.id, seconds: seconds, lapNumber: quickest.bestLapNumber, date: quickest.date,
            car: quickest.car)
    }

    /// How many sessions the logbook has at the circuit: what `{visits}` has always filled with, so a
    /// saved project renders as it did.
    public static func visits(in entries: [LogbookEntry], circuitKey: String) -> Int {
        guard !circuitKey.isEmpty else { return 0 }
        return entries.filter { LogbookFilter.circuitKey(of: $0) == circuitKey }.count
    }

    /// How many track days the logbook has at the circuit (#426): the days it was driven, however
    /// many sessions each, by the day it was entered when a file carries no date.
    public static func trackDays(
        in entries: [LogbookEntry], circuitKey: String? = nil, calendar: Calendar = .current
    ) -> Int {
        if let circuitKey, circuitKey.isEmpty { return 0 }
        return Set(
            entries.filter { entry in circuitKey.map { LogbookFilter.circuitKey(of: entry) == $0 } ?? true }
                .map { calendar.startOfDay(for: $0.date ?? $0.added) }
        ).count
    }

    /// The sessions that set a personal best at their circuit when they were driven — overall or
    /// in their car — in date order, undated sessions last. The season summary counts these.
    public static func entriesSettingBests(in entries: [LogbookEntry]) -> Set<UUID> {
        Set(badges(in: entries).keys)
    }

    /// The Logbook's PB badge for each session that set a personal best when it was driven (#422):
    /// `.current` for the session that still holds the best at its circuit, overall or in its car,
    /// `.former` for one since beaten. Sessions are taken in date order, undated ones last; a lap
    /// that only equals the best does not take it.
    public static func badges(in entries: [LogbookEntry]) -> [UUID: PersonalBestBadge] {
        let ordered = entries.sorted { ($0.date ?? .distantFuture, $0.added) < ($1.date ?? .distantFuture, $1.added) }
        var bestSoFar: [String: (seconds: Double, holder: UUID)] = [:]
        var setters = Set<UUID>()
        for entry in ordered {
            guard let best = entry.bestLap else { continue }
            let key = LogbookFilter.circuitKey(of: entry)
            // No circuit, no personal best there (#455).
            guard !key.isEmpty else { continue }
            // Not "|", which joins a circuit and its configuration (#549).
            for scope in [key, key + "\u{1E}" + entry.car.lowercased()]
            where best < bestSoFar[scope]?.seconds ?? .infinity {
                bestSoFar[scope] = (best, entry.id)
                setters.insert(entry.id)
            }
        }
        let holders = Set(bestSoFar.values.map(\.holder))
        return Dictionary(uniqueKeysWithValues: setters.map { ($0, holders.contains($0) ? .current : .former) })
    }

    /// The logbook's text keys and what Insert Detail calls them (#433), in menu order.
    public static let textKeys: [(key: String, title: String)] = [
        ("pb", "Personal Best"), ("pbDate", "Personal Best Date"), ("pbCar", "Personal Best Car"),
        ("trackDays", "Track Days Here"), ("visits", "Sessions Here"),
    ]

    /// `{pb}`, `{pbDate}`, `{pbCar}`, `{visits}` (sessions) and `{trackDays}` (#433) for a project
    /// whose data is at `circuitKey`,
    /// the personal best in `car` when one is given and the logbook has it, else overall.
    public static func detailKeys(in entries: [LogbookEntry], circuitKey: String, car: String?) -> [String: String] {
        let inCar = car.flatMap { $0.isEmpty ? nil : $0 }.flatMap { best(in: entries, circuitKey: circuitKey, car: $0) }
        guard let best = inCar ?? best(in: entries, circuitKey: circuitKey) else {
            return [
                "visits": String(visits(in: entries, circuitKey: circuitKey)),
                "trackDays": String(trackDays(in: entries, circuitKey: circuitKey)),
            ]
        }
        var keys: [String: String] = [
            "pb": TimeParsingBridge.lapTime(best.seconds),
            "pbCar": best.car,
            "visits": String(visits(in: entries, circuitKey: circuitKey)),
            "trackDays": String(trackDays(in: entries, circuitKey: circuitKey)),
        ]
        if let date = best.date { keys["pbDate"] = date.formatted(date: .abbreviated, time: .omitted) }
        return keys
    }
}

/// `TimeParsing` lives in TelemetryKit; this file keeps ProjectModel's import list unchanged.
enum TimeParsingBridge {
    static func lapTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let rest = seconds - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, rest)
    }
}

extension ProjectDetails {
    /// These details with `extras` added as named extras where no value with that name exists,
    /// so `{pb}` fills from the logbook while a detail the user typed under that name still wins.
    public func adding(_ extras: [String: String]) -> ProjectDetails {
        var result = self
        for (name, value) in extras.sorted(by: { $0.key < $1.key })
        where !result.extras.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            result.extras.append(ProjectDetail(name: name, value: value))
        }
        return result
    }
}

extension Project {
    /// Whether any text names a logbook key, so the compile reads the logbook for it (#351).
    public var usesLogbookKeys: Bool {
        displayObjects.contains { object in
            let text: String
            switch object.kind {
            case .text(let params): text = params.text
            case .statCard(let params): text = params.title
            default: return false
            }
            let lower = text.lowercased()
            return lower.contains("{pb") || lower.contains("{visits") || lower.contains("{trackdays")
        }
    }

    /// Whether a timer measures against the personal best, so the compile loads that lap (#351).
    public var needsPersonalBest: Bool {
        displayObjects.contains { object in
            if case .timer(let params) = object.kind { return params.deltaReference == .personalBest }
            return false
        }
    }
}
