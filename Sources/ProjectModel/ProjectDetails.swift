import Foundation

/// What a project is *of* (#74): the track, the car, the driver, the day. Any text object can show
/// them by naming them in braces — `{track} · {date}` — so a title card in a template reads right
/// in every project without being edited.
///
/// A fixed core that the data can fill in, plus whatever else the owner cares about (tyres, class,
/// setup notes) as named extras, so a new kind of detail never needs a schema change.
///
/// Called *details* rather than attributes because an attribute is already something else here:
/// what a telemetry channel means.
public struct ProjectDetails: Hashable, Codable, Sendable {
    public var track: String
    public var car: String
    public var driver: String
    public var event: String
    /// Practice, qualifying, open lapping, or anything else the organiser calls it.
    public var session: String
    /// The day, as `2026-08-23`: a day at the track rather than an instant, so it reads the same
    /// on a Mac in another time zone. Empty when unknown.
    public var date: String
    public var extras: [ProjectDetail]

    public init(
        track: String = "", car: String = "", driver: String = "", event: String = "", session: String = "",
        date: String = "", extras: [ProjectDetail] = []
    ) {
        self.track = track
        self.car = car
        self.driver = driver
        self.event = event
        self.session = session
        self.date = date
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case track, car, driver, event, session, date, extras
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = try c.decodeIfPresent(String.self, forKey: .track) ?? ""
        car = try c.decodeIfPresent(String.self, forKey: .car) ?? ""
        driver = try c.decodeIfPresent(String.self, forKey: .driver) ?? ""
        event = try c.decodeIfPresent(String.self, forKey: .event) ?? ""
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        extras = try c.decodeIfPresent([ProjectDetail].self, forKey: .extras) ?? []
    }

    public var isEmpty: Bool { self == ProjectDetails() }

    /// The core details as a text object names them, in the order the inspector lists them.
    public static let coreKeys = ["track", "car", "driver", "event", "session", "date"]

    /// The value `{key}` stands for, or `nil` when nothing has been entered for it. Keys match
    /// without regard to case, so `{Track}` and `{tyres}` work as typed.
    public func value(for key: String) -> String? {
        let value: String
        switch key.lowercased() {
        case "track": value = track
        case "car": value = car
        case "driver": value = driver
        case "event": value = event
        case "session": value = session
        case "date": value = Self.displayDate(date) ?? date
        default:
            value = extras.first { $0.name.caseInsensitiveCompare(key) == .orderedSame }?.value ?? ""
        }
        return value.isEmpty ? nil : value
    }

    /// `text` with every `{key}` that has a value replaced by it.
    ///
    /// A key with no value stays as typed, braces and all. That is what makes a title card in a
    /// fresh project say `{car}` rather than quietly nothing, and it is also why no saved project
    /// changes when it is opened: one saved before details existed has none, so any braces in its
    /// text still draw exactly as they did.
    public func fill(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(where: { $0 == "}" || $0 == "{" }), rest[close] == "}"
            else {
                result += rest[open...open]
                rest = rest[afterOpen...]
                continue
            }
            let key = rest[afterOpen..<close].trimmingCharacters(in: .whitespaces)
            result += value(for: key) ?? String(rest[open...close])
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    /// `2026-08-23` as this Mac writes a date — "23 Aug 2026", "Aug 23, 2026" — or `nil` when the
    /// text is not a date.
    public static func displayDate(_ iso: String) -> String? {
        day(iso)?.formatted(date: .abbreviated, time: .omitted)
    }

    /// Noon on the day `iso` names, in this Mac's calendar: noon so no time zone moves it a day.
    public static func day(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// These details with every blank core field taken from `suggested`, and the names of the
    /// fields that were filled, for the status line. Never overwrites: what the driver typed beats
    /// whatever a file says.
    public func fillingBlanks(from suggested: ProjectDetails) -> (details: ProjectDetails, filled: [String]) {
        var result = self
        var filled: [String] = []
        let fields: [(String, WritableKeyPath<ProjectDetails, String>)] = [
            ("track", \.track), ("car", \.car), ("driver", \.driver), ("event", \.event),
            ("session", \.session), ("date", \.date),
        ]
        for (name, field) in fields where result[keyPath: field].isEmpty && !suggested[keyPath: field].isEmpty {
            result[keyPath: field] = suggested[keyPath: field]
            filled.append(name)
        }
        return (result, filled)
    }

    /// The day `date` falls on here, as the details store it.
    public static func iso(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// A detail the owner named: `Tyres` — `Michelin Cup 2`.
public struct ProjectDetail: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

extension DisplayObjectKind {
    /// This object with `details` filled into its text. Only a text object has text of its own to
    /// fill; a readout's label names a channel and stays as it is.
    public func filling(_ details: ProjectDetails) -> DisplayObjectKind {
        guard !details.isEmpty else { return self }
        switch self {
        case .text(var params):
            params.text = details.fill(params.text)
            return .text(params)
        case .statCard(var params):
            params.title = details.fill(params.title)
            return .statCard(params)
        default:
            return self
        }
    }
}
