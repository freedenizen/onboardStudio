import Foundation
import TelemetryKit

/// Reads RaceChrono / RaceChrono Pro CSV exports (format 3, with best-effort support for 2).
///
/// Layout of a v3 file:
/// ```
/// This file is created using RaceChrono Pro v9.1.3 ( http://racechrono.com/ ).
/// Format,3
/// Session title,"Tianma"
/// Session type,Lap timing
/// Track name,"Tianma"
/// Driver name,
/// Created,31/12/2025,02:54
/// Note,
///
/// timestamp,fragment_id,lap_number,elapsed_time,distance_traveled,altitude,...,speed,...,rpm,...
/// unix time,,,s,m,m,...,m/s,...,rpm,...
/// ,,,,,100: gps,...,calc,...,200: obd,...
/// 1767150797.44,0,8,1149.08,17834.748,1.1,...
/// ```
/// Column names repeat across sources (`speed` from GPS, calc and OBD). The first occurrence of a
/// role keeps it; later duplicates become aux channels named with their source.
public struct RaceChronoCSVImporter: TelemetryImporter {
    public static let id = "racechrono-csv"
    public static let displayName = "RaceChrono CSV"
    public static let fileExtensions = ["csv"]

    static let signature = "This file is created using RaceChrono"

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        if sniff.firstLine.hasPrefix(signature) { return .certain }
        return sniff.head.contains("\ntimestamp,") && sniff.head.contains("lap_number") ? .likely : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        let text = try CSVReader.loadText(from: url)
        let lines = CSVReader.lines(of: text[...])
        let reader = CSVReader(delimiter: .comma)

        let preamble = Self.parsePreamble(lines, reader: reader, fileName: url.lastPathComponent)
        guard let headerLine = preamble.headerLine else { throw ImportError.missingHeader("timestamp row") }
        let header = reader.fields(of: lines[headerLine]).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let timeIndex = header.firstIndex(of: "timestamp") else { throw ImportError.missingColumn("timestamp") }

        let layout = Self.parseLayoutRows(lines, after: headerLine, format: preamble.format, reader: reader)
        let (times, rows) = Self.dataRows(lines[layout.firstDataLine...], reader: reader, timeIndex: timeIndex)
        guard !times.isEmpty else { throw ImportError.noData }

        var columns: [RawColumn] = []
        for (index, name) in header.enumerated() where index != timeIndex && !name.isEmpty {
            let unitText = index < layout.units.count ? layout.units[index] : ""
            let sourceText =
                index < layout.sources.count ? layout.sources[index].trimmingCharacters(in: .whitespaces) : ""
            let mapping = Self.mapping(for: name, unitText: unitText, source: sourceText)
            let values = rows.map { row -> Double? in index < row.count ? CSVReader.number(row[index]) : nil }
            columns.append(
                RawColumn(
                    name: name,
                    unit: mapping.unit,
                    source: sourceText.isEmpty ? nil : sourceText,
                    suggestedRole: mapping.role,
                    interpolation: mapping.interpolation,
                    values: values
                ))
        }
        return RawTable(info: preamble.info, times: times, columns: columns)
    }

    // MARK: - Parsing stages

    struct Preamble {
        var info: SessionInfo
        var format = 3
        var headerLine: Int?
    }

    /// Reads the `Key,Value` lines before the header row (which starts with `timestamp`).
    static func parsePreamble(_ lines: [Substring], reader: CSVReader, fileName: String) -> Preamble {
        var preamble = Preamble(info: SessionInfo(sourceFormat: displayName, sourceFileName: fileName))
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("timestamp") {
                preamble.headerLine = index
                break
            }
            let fields = reader.fields(of: line)
            guard fields.count >= 2 else { continue }
            let value = fields[1].trimmingCharacters(in: .whitespaces)
            let optional = value.isEmpty ? nil : value
            switch fields[0].lowercased() {
            case "format": preamble.format = Int(value) ?? 3
            case "session title": preamble.info.title = optional
            case "track name": preamble.info.trackName = optional
            case "driver name": preamble.info.driverName = optional
            case "note": preamble.info.notes = optional
            case "created": preamble.info.createdAt = parseCreated(fields.dropFirst())
            default: break
            }
        }
        return preamble
    }

    struct Layout {
        var units: [String] = []
        var sources: [String] = []
        var firstDataLine: Int
    }

    /// Format 3 places a units row and a data-source row after the header; both are optional.
    static func parseLayoutRows(_ lines: [Substring], after headerLine: Int, format: Int, reader: CSVReader) -> Layout {
        var layout = Layout(firstDataLine: headerLine + 1)
        guard format >= 3 else { return layout }
        if layout.firstDataLine < lines.count, !looksNumericRow(lines[layout.firstDataLine]) {
            layout.units = reader.fields(of: lines[layout.firstDataLine])
            layout.firstDataLine += 1
        }
        if layout.firstDataLine < lines.count, !looksNumericRow(lines[layout.firstDataLine]) {
            layout.sources = reader.fields(of: lines[layout.firstDataLine])
            layout.firstDataLine += 1
        }
        return layout
    }

    /// Parses data rows, dropping blank lines, unparsable timestamps and duplicate/out-of-order rows.
    static func dataRows(_ lines: ArraySlice<Substring>, reader: CSVReader, timeIndex: Int) -> (
        times: [Double], rows: [[String]]
    ) {
        var times: [Double] = []
        var rows: [[String]] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let fields = reader.fields(of: line)
            guard fields.count > timeIndex, let time = CSVReader.number(fields[timeIndex]) else { continue }
            if let last = times.last, time <= last { continue }
            times.append(time)
            rows.append(fields)
        }
        return (times, rows)
    }

    // MARK: - Helpers

    static func looksNumericRow(_ line: Substring) -> Bool {
        guard let first = line.split(separator: ",", omittingEmptySubsequences: false).first else { return false }
        return Double(first.trimmingCharacters(in: .whitespaces)) != nil
    }

    /// `Created,31/12/2025,02:54` → date (RaceChrono uses day/month/year and 24-hour time).
    static func parseCreated(_ fields: ArraySlice<String>) -> Date? {
        let joined = fields.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for pattern in ["dd/MM/yyyy HH:mm", "dd/MM/yyyy HH:mm:ss", "yyyy-MM-dd HH:mm", "MM/dd/yyyy HH:mm"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: joined) { return date }
        }
        return nil
    }

    struct Mapping {
        var role: ChannelRole?
        var unit: TelemetryUnit
        var interpolation: InterpolationPolicy = .linear
    }

    static func mapping(for name: String, unitText: String, source: String) -> Mapping {
        let unit = TelemetryUnit(parsing: unitText)
        let isOBD = source.lowercased().contains("obd")
        switch name.lowercased() {
        case "lap_number": return Mapping(role: .lap, unit: .count, interpolation: .step)
        case "elapsed_time": return Mapping(role: .aux("elapsed_time"), unit: .seconds)
        case "distance_traveled", "distance": return Mapping(role: .distance, unit: unit == .none ? .meters : unit)
        case "altitude": return Mapping(role: .altitude, unit: unit == .none ? .meters : unit)
        case "bearing", "heading": return Mapping(role: .heading, unit: .degrees)
        case "latitude": return Mapping(role: .latitude, unit: .degrees)
        case "longitude": return Mapping(role: .longitude, unit: .degrees)
        case "speed": return Mapping(role: isOBD ? .obd(name) : .speed, unit: unit == .none ? .metersPerSecond : unit)
        case "lateral_acc": return Mapping(role: .lateralG, unit: .gForce)
        case "longitudinal_acc": return Mapping(role: .longitudinalG, unit: .gForce)
        case "rpm": return Mapping(role: .rpm, unit: .rpm)
        case "throttle_pos", "throttle": return Mapping(role: .throttle, unit: .percent)
        case "brake_pos", "brake": return Mapping(role: .brake, unit: .percent)
        case "gear": return Mapping(role: .gear, unit: .count, interpolation: .step)
        case "coordinate_precision": return Mapping(role: .accuracy, unit: .custom("DOP"))
        case "fragment_id", "fix_type", "satellites":
            return Mapping(role: .aux(name), unit: unit, interpolation: .step)
        default: return Mapping(role: isOBD ? .obd(name) : .aux(name), unit: unit)
        }
    }
}
