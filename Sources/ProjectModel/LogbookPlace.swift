import Foundation

/// Where the Logbook window was: what the sidebar had chosen, which view, and the sessions
/// selected (#701). The window came back on All Sessions with nothing selected after every quit;
/// it is kept in the preferences, so the Logbook returns to its place whether or not macOS is
/// set to bring windows back.
public struct LogbookPlace: Codable, Equatable, Sendable {
    public var scope: LogbookScope
    /// The view's raw value: `sessions`, `trends`, `season` or `analysis`.
    public var view: String
    public var selection: [UUID]

    public static let start = LogbookPlace(scope: .all, view: "sessions", selection: [])

    public init(scope: LogbookScope, view: String, selection: [UUID]) {
        self.scope = scope
        self.view = view
        self.selection = selection
    }

    /// As the preferences keep it.
    public var storageValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// `nil` for nothing kept, or for words an earlier or a later build wrote that this one
    /// cannot read: the window then opens where it always did.
    public init?(storageValue: String) {
        guard let data = storageValue.data(using: .utf8), !data.isEmpty,
            let place = try? JSONDecoder().decode(LogbookPlace.self, from: data)
        else { return nil }
        self = place
    }

    /// The place as the logbook now has it. A day, a circuit, a car or a year that is no longer
    /// there gives way to All Sessions, a day renamed since takes its new label, and the
    /// selection keeps only the sessions that still exist and that the sidebar's choice shows.
    public func resolved(in entries: [LogbookEntry], days: [TrackDay], cars: [Car]) -> LogbookPlace {
        var place = self
        switch scope {
        case .all: break
        case .day(let id, _):
            if let day = days.first(where: { $0.id == id }) {
                place.scope = .day(id: id, title: day.label)
            } else {
                place.scope = .all
            }
        case .circuit, .year:
            if !entries.contains(where: { LogbookFilter.matches($0, scope: scope) }) { place.scope = .all }
        case .car(let name):
            let known = LogbookFilter.cars(in: entries, garage: cars).contains { $0.scope == .car(name) }
            if !known { place.scope = .all }
        }
        let shown = Set(entries.filter { LogbookFilter.matches($0, scope: place.scope) }.map(\.id))
        place.selection = selection.filter(shown.contains)
        return place
    }
}

extension LogbookScope: Codable {
    private enum Kind: String, Codable { case all, circuit, car, year, day }
    private enum CodingKeys: String, CodingKey { case kind, id, title, year }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .all: self = .all
        case .circuit:
            self = .circuit(
                id: try container.decode(String.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title))
        case .car: self = .car(try container.decode(String.self, forKey: .title))
        case .year: self = .year(try container.decode(Int.self, forKey: .year))
        case .day:
            self = .day(
                id: try container.decode(UUID.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all: try container.encode(Kind.all, forKey: .kind)
        case .circuit(let id, let title):
            try container.encode(Kind.circuit, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        case .car(let name):
            try container.encode(Kind.car, forKey: .kind)
            try container.encode(name, forKey: .title)
        case .year(let year):
            try container.encode(Kind.year, forKey: .kind)
            try container.encode(year, forKey: .year)
        case .day(let id, let title):
            try container.encode(Kind.day, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        }
    }
}
