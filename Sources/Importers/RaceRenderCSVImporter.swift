import Foundation
import TelemetryKit

/// Reads RaceRender's native CSV format (also produced by TrackAddict and other tools).
///
/// Format summary (racerender.com/Developer/DataFormat.html):
/// - Optional first line `# RaceRender Data`; other `#` lines are comments.
/// - `# Lap N: hh:mm:ss.nn` tags mark the end of lap N (chronological).
/// - Header row, then data rows. `Time` is required (seconds or `hh:mm:ss.nn`).
/// - Known columns: Longitude, Latitude, Altitude, GPS_Update, GPS_Delay, X (long G), Y (lat G),
///   MPH | KPH | Speed (m/s), Heading, Lap, RPM, Gear, Accuracy, Throttle, Brake.
/// - `*OBD` suffix marks OBD-sourced columns; `OBD_Update` flags fresh OBD samples.
public struct RaceRenderCSVImporter: TelemetryImporter {
    public static let id = "racerender-csv"
    public static let displayName = "RaceRender CSV"
    public static let fileExtensions = ["csv", "txt"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        if sniff.firstLine.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("# racerender data") {
            return .certain
        }
        guard fileExtensions.contains(sniff.fileExtension) else { return .no }
        // Look for a header line with a Time column and at least one known column.
        let lines = CSVReader.lines(of: sniff.head[...]).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        guard let header = lines.first else { return .no }
        let names = Set(
            CSVReader(delimiter: CSVReader.detectDelimiter(in: sniff.head[...])).fields(of: header)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        guard names.contains("time") else { return .no }
        let known: Set<String> = ["latitude", "longitude", "mph", "kph", "speed", "rpm", "x", "y", "heading", "lap"]
        return names.isDisjoint(with: known) ? .possible : .likely
    }

    public func importFile(at url: URL) throws -> RawTable {
        let text = try CSVReader.loadText(from: url)
        let reader = CSVReader(delimiter: CSVReader.detectDelimiter(in: text[...]))
        let parsed = Self.splitLines(CSVReader.lines(of: text[...]), reader: reader)
        guard let header = parsed.header else { throw ImportError.missingHeader("column names") }
        guard let timeIndex = header.firstIndex(where: { $0.caseInsensitiveCompare("Time") == .orderedSame })
        else { throw ImportError.missingColumn("Time") }
        let (times, rows) = Self.timeAxis(rows: parsed.rows, timeIndex: timeIndex)
        guard !times.isEmpty else { throw ImportError.noData }
        let columns = Self.columns(header: header, rows: rows, timeIndex: timeIndex)
        let info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        return RawTable(info: info, times: times, columns: columns, lapMarkers: parsed.lapMarkers)
    }

    // MARK: - Parsing stages

    struct ParsedLines {
        var header: [String]?
        var rows: [[String]] = []
        var lapMarkers: [RawLapMarker] = []
    }

    /// Separates comment/lap-tag lines from the header and data rows.
    static func splitLines(_ lines: [Substring], reader: CSVReader) -> ParsedLines {
        var parsed = ParsedLines()
        parsed.rows.reserveCapacity(lines.count)
        for line in lines {
            if line.hasPrefix("#") {
                if let marker = lapMarker(from: line) { parsed.lapMarkers.append(marker) }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let fields = reader.fields(of: line)
            if parsed.header == nil {
                parsed.header = fields.map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parsed.rows.append(fields)
            }
        }
        return parsed
    }

    /// Parses the time column and keeps only rows whose time is strictly increasing.
    static func timeAxis(rows: [[String]], timeIndex: Int) -> (times: [Double], rows: [[String]]) {
        var times: [Double] = []
        var kept: [[String]] = []
        times.reserveCapacity(rows.count)
        kept.reserveCapacity(rows.count)
        for row in rows where row.count > timeIndex {
            guard let time = TimeParsing.seconds(from: row[timeIndex]) else { continue }
            if let last = times.last, time <= last { continue }
            times.append(time)
            kept.append(row)
        }
        return (times, kept)
    }

    static func columns(header: [String], rows: [[String]], timeIndex: Int) -> [RawColumn] {
        var columns: [RawColumn] = []
        for (index, rawName) in header.enumerated() where index != timeIndex {
            var name = rawName
            var isOBD = false
            if name.lowercased().hasSuffix("*obd") {
                isOBD = true
                name = String(name.dropLast(4)).trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty else { continue }
            let mapping = mapping(for: name, isOBD: isOBD)
            let values = rows.map { row -> Double? in index < row.count ? CSVReader.number(row[index]) : nil }
            columns.append(
                RawColumn(
                    name: name,
                    unit: mapping.unit,
                    source: isOBD ? "obd" : nil,
                    suggestedRole: mapping.role,
                    interpolation: mapping.interpolation,
                    values: values
                ))
        }
        return columns
    }

    // MARK: - Helpers

    /// Parses `# Lap 3: 00:02:23.07` (case-insensitive, flexible spacing).
    static func lapMarker(from line: Substring) -> RawLapMarker? {
        let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard body.lowercased().hasPrefix("lap ") else { return nil }
        let rest = body.dropFirst(4)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        guard let number = Int(rest[..<colon].trimmingCharacters(in: .whitespaces)) else { return nil }
        guard let time = TimeParsing.seconds(from: String(rest[rest.index(after: colon)...])) else { return nil }
        return RawLapMarker(number: number, time: time)
    }

    struct Mapping {
        var role: ChannelRole?
        var unit: TelemetryUnit
        var interpolation: InterpolationPolicy = .linear
    }

    static func mapping(for name: String, isOBD: Bool) -> Mapping {
        let key = name.lowercased()
        let mapping: Mapping =
            switch key {
            case "longitude", "lon", "long": Mapping(role: .longitude, unit: .degrees)
            case "latitude", "lat": Mapping(role: .latitude, unit: .degrees)
            case "altitude", "alt": Mapping(role: .altitude, unit: .meters)
            case "gps_update": Mapping(role: .gpsUpdate, unit: .none, interpolation: .step)
            case "gps_delay": Mapping(role: .gpsDelay, unit: .seconds)
            case "x", "accel_x", "longitudinal_g": Mapping(role: .longitudinalG, unit: .gForce)
            case "y", "accel_y", "lateral_g": Mapping(role: .lateralG, unit: .gForce)
            case "mph": Mapping(role: .speed, unit: .milesPerHour)
            case "kph", "km/h", "kmh": Mapping(role: .speed, unit: .kilometersPerHour)
            case "speed", "speed (m/s)", "speed_mps": Mapping(role: .speed, unit: .metersPerSecond)
            case "heading", "bearing", "course": Mapping(role: .heading, unit: .degrees)
            case "lap": Mapping(role: .lap, unit: .count, interpolation: .step)
            case "rpm", "engine rpm": Mapping(role: .rpm, unit: .rpm)
            case "gear": Mapping(role: .gear, unit: .count, interpolation: .step)
            case "accuracy": Mapping(role: .accuracy, unit: .meters)
            case "throttle", "throttle position": Mapping(role: .throttle, unit: .percent)
            case "brake", "brake position": Mapping(role: .brake, unit: .percent)
            case "obd_update": Mapping(role: .aux("OBD_Update"), unit: .none, interpolation: .step)
            default: Mapping(role: isOBD ? .obd(name) : .aux(name), unit: .none)
            }
        return mapping
    }
}
