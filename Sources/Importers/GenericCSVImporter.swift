import Foundation
import TelemetryKit

/// Reads CSV/TSV exports from apps that are not explicitly supported, using header profiles for
/// the common ones (Harry's LapTimer, TrackAddict non-RaceRender export, AIM, MoTeC i2) and a
/// fuzzy name match otherwise. Time may be absolute (unix), relative seconds, or `hh:mm:ss.nn`.
public struct GenericCSVImporter: TelemetryImporter {
    public static let id = "generic-csv"
    public static let displayName = "Generic CSV"
    public static let fileExtensions = ["csv", "txt", "tsv"]

    public init() {}

    /// A known app's header vocabulary.
    struct Profile: Sendable {
        let name: String
        /// Any of these substrings in the first 2 KB marks the profile as certain.
        let signatures: [String]
        /// Column-name (lowercased) → role/unit.
        let names: [String: (ChannelRole, TelemetryUnit)]
    }

    static let profiles: [Profile] = [
        Profile(
            name: "Harry's LapTimer",
            signatures: ["harry's laptimer", "harryslaptimer", "laptimer"],
            names: [
                "time": (.time, .seconds), "date time": (.time, .seconds), "latitude": (.latitude, .degrees),
                "longitude": (.longitude, .degrees), "speed": (.speed, .kilometersPerHour),
                "speed (km/h)": (.speed, .kilometersPerHour),
                "speed (mph)": (.speed, .milesPerHour), "heading": (.heading, .degrees),
                "altitude": (.altitude, .meters),
                "lap": (.lap, .count), "rpm": (.rpm, .rpm), "throttle": (.throttle, .percent), "gear": (.gear, .count),
                "lateral": (.lateralG, .gForce), "longitudinal": (.longitudinalG, .gForce),
                "distance": (.distance, .meters),
            ]),
        Profile(
            name: "AIM",
            signatures: ["aim", "racestudio", "mychron", "solo 2", "solo2"],
            names: [
                "time": (.time, .seconds), "gps latitude": (.latitude, .degrees),
                "gps longitude": (.longitude, .degrees),
                "gps speed": (.speed, .kilometersPerHour), "gps heading": (.heading, .degrees),
                "gps altitude": (.altitude, .meters),
                "gps latacc": (.lateralG, .gForce), "gps lonacc": (.longitudinalG, .gForce), "rpm": (.rpm, .rpm),
                "gear": (.gear, .count), "throttle": (.throttle, .percent), "lap": (.lap, .count),
            ]),
        Profile(
            name: "MoTeC i2",
            signatures: ["motec", "i2 pro", "workbook"],
            names: [
                "time": (.time, .seconds), "gps latitude": (.latitude, .degrees),
                "gps longitude": (.longitude, .degrees),
                "gps speed": (.speed, .kilometersPerHour), "ground speed": (.speed, .kilometersPerHour),
                "engine rpm": (.rpm, .rpm),
                "throttle pos": (.throttle, .percent), "gear": (.gear, .count), "g force lat": (.lateralG, .gForce),
                "g force long": (.longitudinalG, .gForce), "lap number": (.lap, .count),
                "corr dist": (.distance, .meters),
            ]),
    ]

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        guard fileExtensions.contains(sniff.fileExtension) else { return .no }
        let lowered = sniff.head.lowercased()
        if profiles.contains(where: { profile in profile.signatures.contains { lowered.contains($0) } }) {
            return .likely
        }
        let names = headerNames(in: sniff.head)
        let hasTime = names.contains { $0.contains("time") }
        let hasPosition = names.contains { $0.contains("lat") } && names.contains { $0.contains("lon") }
        return hasTime && (hasPosition || names.contains { $0.contains("speed") }) ? .possible : .no
    }

    static func headerNames(in text: String) -> [String] {
        let delimiter = CSVReader.detectDelimiter(in: text[...])
        let reader = CSVReader(delimiter: delimiter)
        for line in CSVReader.lines(of: text[...]).prefix(40) {
            let fields = reader.fields(of: line).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if fields.count >= 3, fields.contains(where: { $0.contains("time") }) { return fields }
        }
        return []
    }

    public func importFile(at url: URL) throws -> RawTable {
        let text = try CSVReader.loadText(from: url)
        let reader = CSVReader(delimiter: CSVReader.detectDelimiter(in: text[...]))
        let lines = CSVReader.lines(of: text[...])
        let lowered = text.prefix(2048).lowercased()
        let profile = Self.profiles.first { profile in profile.signatures.contains { lowered.contains($0) } }

        // Header: the first line with ≥3 fields containing a time-like column.
        var headerIndex: Int?
        var header: [String] = []
        for (index, line) in lines.prefix(60).enumerated() {
            let fields = reader.fields(of: line).map { $0.trimmingCharacters(in: .whitespaces) }
            if fields.count >= 3, fields.contains(where: { $0.lowercased().contains("time") }) {
                headerIndex = index
                header = fields
                break
            }
        }
        guard let headerIndex else { throw ImportError.missingHeader("a row with a Time column") }
        // Skip unit rows that follow the header (non-numeric first field).
        var firstData = headerIndex + 1
        while firstData < lines.count,
            reader.fields(of: lines[firstData]).first.flatMap({ CSVReader.number($0) ?? TimeParsing.seconds(from: $0) })
                == nil
        {
            firstData += 1
            if firstData - headerIndex > 4 { break }
        }
        let timeIndex = header.firstIndex { Self.isTimeColumn($0) } ?? 0
        var times: [Double] = []
        var rows: [[String]] = []
        for line in lines[firstData...] {
            let fields = reader.fields(of: line)
            guard fields.count > timeIndex, let t = TimeParsing.seconds(from: fields[timeIndex]) else { continue }
            if let last = times.last, t <= last { continue }
            times.append(t)
            rows.append(fields)
        }
        guard !times.isEmpty else { throw ImportError.noData }
        var columns: [RawColumn] = []
        for (index, name) in header.enumerated() where index != timeIndex && !name.isEmpty {
            let (role, unit) = Self.mapping(name, profile: profile)
            let values = rows.map { row -> Double? in index < row.count ? CSVReader.number(row[index]) : nil }
            let step = role == .lap || role == .gear
            columns.append(
                RawColumn(
                    name: name, unit: unit, suggestedRole: role, interpolation: step ? .step : .linear, values: values))
        }
        let info = SessionInfo(
            sourceFormat: profile.map { "\(Self.displayName) (\($0.name))" } ?? Self.displayName,
            sourceFileName: url.lastPathComponent)
        return RawTable(info: info, times: times, columns: columns)
    }

    static func isTimeColumn(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == "time" || n.hasPrefix("time ") || n.hasPrefix("time(") || n.contains("timestamp")
            || n == "date time" || n == "elapsed time"
    }

    /// Profile lookup first, then a fuzzy match on common words; units come from a trailing
    /// parenthesised unit when present.
    static func mapping(_ rawName: String, profile: Profile?) -> (ChannelRole?, TelemetryUnit) {
        var name = rawName.lowercased().trimmingCharacters(in: .whitespaces)
        var unit = TelemetryUnit.none
        if let open = name.lastIndex(of: "("), name.hasSuffix(")"),
            name.index(after: open) <= name.index(before: name.endIndex)
        {
            unit = TelemetryUnit(parsing: String(name[name.index(after: open)..<name.index(before: name.endIndex)]))
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }
        if let profile, let hit = profile.names[name] ?? profile.names[rawName.lowercased()] {
            return (hit.0, unit == .none ? hit.1 : unit)
        }
        return fuzzyRole(name: name, unit: unit) ?? (.aux(rawName), unit)
    }

    static func fuzzyRole(name: String, unit: TelemetryUnit) -> (ChannelRole?, TelemetryUnit)? {
        func has(_ words: String...) -> Bool { words.allSatisfy { name.contains($0) } }
        let isAccel = has("acc") || has(" g") || name.hasSuffix("g")
        if has("lat") && !isAccel { return (.latitude, .degrees) }
        if has("lon") && !isAccel { return (.longitude, .degrees) }
        if has("speed") || has("velocity") || name == "mph" || name == "kph" {
            let fallback: TelemetryUnit =
                name.contains("mph")
                ? .milesPerHour : (name.contains("kph") || name.contains("km") ? .kilometersPerHour : .metersPerSecond)
            return (.speed, unit != .none ? unit : fallback)
        }
        if has("heading") || has("bearing") || has("course") { return (.heading, .degrees) }
        if has("alt") || has("elev") { return (.altitude, unit == .none ? .meters : unit) }
        let simple: [String: (ChannelRole, TelemetryUnit)] = [
            "lap": (.lap, .count), "rpm": (.rpm, .rpm), "gear": (.gear, .count), "throttle": (.throttle, .percent),
            "tps": (.throttle, .percent), "brake": (.brake, .percent),
        ]
        if let hit = simple.first(where: { name.contains($0.key) }) { return hit.value }
        if has("lat") && isAccel { return (.lateralG, .gForce) }
        if (has("lon") || has("long")) && isAccel { return (.longitudinalG, .gForce) }
        if has("dist") { return (.distance, unit == .none ? .meters : unit) }
        return nil
    }

}
