import Foundation
import TelemetryKit

/// Reads Racelogic VBO files: a `[header]` block listing channels, optional `[column names]`,
/// and a `[data]` block of space-separated rows. Time is `hhmmss.ss` UTC; lat/long are in
/// minutes (VBO convention) unless a `[column names]` header indicates degrees.
public struct VBOImporter: TelemetryImporter {
    public static let id = "vbo"
    public static let displayName = "Racelogic VBO"
    public static let fileExtensions = ["vbo"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        if sniff.head.contains("[header]") && sniff.head.contains("[data]") || sniff.head.contains("[header]") {
            return .certain
        }
        return fileExtensions.contains(sniff.fileExtension) ? .possible : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        let text = try CSVReader.loadText(from: url)
        var section = ""
        var headerNames: [String] = []
        var columnNames: [String] = []
        var unitLines: [String] = []
        var rows: [[String]] = []
        var created: Date?
        for rawLine in CSVReader.lines(of: text[...]) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                section = line.lowercased()
                continue
            }
            switch section {
            case "[header]": headerNames.append(line)
            case "[channel units]": unitLines.append(line)
            case "[column names]":
                columnNames = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            case "[data]": rows.append(line.split(separator: " ", omittingEmptySubsequences: true).map(String.init))
            default:
                if section.isEmpty, created == nil, line.lowercased().hasPrefix("file created on") {
                    created = Self.creationDate(line)
                }
            }
        }
        let names = columnNames.isEmpty ? headerNames : columnNames
        guard !names.isEmpty else { throw ImportError.missingHeader("[header]") }
        let declared = Self.declaredUnits(header: headerNames, units: unitLines, columns: names.count)
        guard let timeIndex = names.firstIndex(where: { $0.lowercased() == "time" }) else {
            throw ImportError.missingColumn("time")
        }
        var times: [Double] = []
        var kept: [[String]] = []
        for row in rows where row.count > timeIndex {
            guard let t = Self.timeSeconds(row[timeIndex]) else { continue }
            if let last = times.last, t <= last { continue }
            times.append(t)
            kept.append(row)
        }
        guard !times.isEmpty else { throw ImportError.noData }
        let origin = times[0]
        let relative = times.map { $0 - origin }
        var columns: [RawColumn] = []
        for (index, name) in names.enumerated() where index != timeIndex {
            let mapping = Self.mapping(name)
            let values = kept.map { row -> Double? in
                guard index < row.count, let v = CSVReader.number(row[index]) else { return nil }
                return mapping.scale(v)
            }
            columns.append(
                RawColumn(
                    name: name, unit: declared[index] ?? mapping.unit, suggestedRole: mapping.role,
                    interpolation: mapping.step ? .step : .linear, values: values))
        }
        var info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        info.createdAt = created
        return RawTable(info: info, times: relative, columns: columns)
    }

    /// The unit the file declares for each column, or `nil` where it declares none.
    ///
    /// Two places say it, and both are easy to miss:
    ///
    /// - **`[channel units]` is right-aligned with `[header]`.** It carries one line per
    ///   *extra* channel and none for the leading GPS ones, so a VBVDHD2 log with 35 channels
    ///   lists 25 units and they belong to the last 25. Aligning from the top instead would give
    ///   every CAN channel its neighbour's unit — bar for a temperature, rpm for a pressure —
    ///   which is worse than having no unit at all, because it looks right.
    /// - **The `[header]` name carries the unit where `[column names]` does not.** A file logs
    ///   `velocity kmh` or `velocity knots`, and both collapse to `velocity` in `[column names]`.
    ///   Guessing km/h for a knots file is wrong by a factor of 1.852 and silent.
    ///
    /// `(null)` is how the format writes "no unit"; it must not become a unit named `(null)`.
    static func declaredUnits(header: [String], units: [String], columns: Int) -> [TelemetryUnit?] {
        var declared = [TelemetryUnit?](repeating: nil, count: columns)
        let offset = header.count - units.count
        for (index, name) in header.enumerated() where index < columns {
            if let fromName = unitSuffix(of: name) { declared[index] = fromName }
            let unitIndex = index - offset
            guard offset >= 0, unitIndex >= 0, unitIndex < units.count else { continue }
            let text = units[unitIndex].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.lowercased() != "(null)" else { continue }
            declared[index] = TelemetryUnit(parsing: text)
        }
        return declared
    }

    /// The unit trailing a `[header]` channel name — `velocity kmh`, `vertical velocity m/s`,
    /// `yaw rate deg/s` — or `nil` when the last word is part of the name (`Air Fuel Ratio`).
    static func unitSuffix(of name: String) -> TelemetryUnit? {
        let words = name.split(separator: " ")
        guard words.count > 1, let last = words.last else { return nil }
        let unit = TelemetryUnit(parsing: String(last))
        if case .custom = unit { return nil }
        return unit == .none ? nil : unit
    }

    struct Mapping {
        var role: ChannelRole?
        var unit: TelemetryUnit
        var step = false
        var scale: (Double) -> Double = { $0 }
    }

    static func mapping(_ name: String) -> Mapping {
        switch name.lowercased() {
        case "lat": Mapping(role: .latitude, unit: .degrees) { $0 / 60 }
        case "long": Mapping(role: .longitude, unit: .degrees) { -$0 / 60 }  // VBO: west positive
        case "velocity", "speed": Mapping(role: .speed, unit: .kilometersPerHour)
        case "heading": Mapping(role: .heading, unit: .degrees)
        case "height", "altitude": Mapping(role: .altitude, unit: .meters)
        case "sats": Mapping(role: .aux("Satellites"), unit: .count, step: true)
        case "longacc", "long_acc": Mapping(role: .longitudinalG, unit: .gForce)
        case "latacc", "lat_acc": Mapping(role: .lateralG, unit: .gForce)
        case "lapnumber", "lap": Mapping(role: .lap, unit: .count, step: true)
        case "rpm": Mapping(role: .rpm, unit: .rpm)
        case "throttle": Mapping(role: .throttle, unit: .percent)
        case "brake": Mapping(role: .brake, unit: .percent)
        case "gear": Mapping(role: .gear, unit: .count, step: true)
        case "distance": Mapping(role: .distance, unit: .meters)
        default: Mapping(role: .aux(name), unit: .none)
        }
    }

    /// `hhmmss.ss` → seconds since midnight.
    static func timeSeconds(_ field: String) -> Double? {
        guard let value = Double(field) else { return nil }
        let hh = floor(value / 10000)
        let mm = floor((value - hh * 10000) / 100)
        return hh * 3600 + mm * 60 + (value - hh * 10000 - mm * 100)
    }

    /// `File created on 23/08/2026 at 16:36:04`
    static func creationDate(_ line: String) -> Date? {
        let pattern = #"(\d{2})/(\d{2})/(\d{4}) at (\d{2}):(\d{2}):(\d{2})"#
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        let parts = line[match].components(separatedBy: CharacterSet(charactersIn: "/ :at")).compactMap { Int($0) }
        guard parts.count >= 6 else { return nil }
        var components = DateComponents()
        components.day = parts[0]
        components.month = parts[1]
        components.year = parts[2]
        components.hour = parts[3]
        components.minute = parts[4]
        components.second = parts[5]
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
