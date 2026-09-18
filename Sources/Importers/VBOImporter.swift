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
                    name: name, unit: mapping.unit, suggestedRole: mapping.role,
                    interpolation: mapping.step ? .step : .linear, values: values))
        }
        var info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        info.createdAt = created
        return RawTable(info: info, times: relative, columns: columns)
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
