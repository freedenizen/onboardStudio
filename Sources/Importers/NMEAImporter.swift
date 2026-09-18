import Foundation
import TelemetryKit

/// Reads NMEA 0183 logs (RMC, GGA, GLL sentences). Time comes from the sentences' UTC fields;
/// the date from RMC when present. Speed and course come from RMC, altitude/fix/satellites from GGA.
public struct NMEAImporter: TelemetryImporter {
    public static let id = "nmea"
    public static let displayName = "NMEA 0183"
    public static let fileExtensions = ["nmea", "txt", "log"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        let lines = sniff.head.split(whereSeparator: \.isNewline).prefix(20)
        let nmeaLines = lines.filter { $0.hasPrefix("$GP") || $0.hasPrefix("$GN") || $0.hasPrefix("$GL") }
        if nmeaLines.count >= 3 { return .certain }
        return nmeaLines.isEmpty ? .no : .likely
    }

    struct Fix {
        var seconds: Double
        var latitude: Double?
        var longitude: Double?
        var speed: Double?
        var course: Double?
        var altitude: Double?
        var satellites: Double?
        var fixQuality: Double?
        var hdop: Double?
    }

    public func importFile(at url: URL) throws -> RawTable {
        let text = try CSVReader.loadText(from: url)
        var fixes: [Double: Fix] = [:]
        var order: [Double] = []
        var dayOffset = 0.0
        var lastSeconds = -1.0
        var date: Date?
        for line in CSVReader.lines(of: text[...]) {
            guard line.hasPrefix("$") else { continue }
            let body = line.split(separator: "*", maxSplits: 1).first.map(String.init) ?? String(line)
            let fields = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let type = fields.first, type.count >= 6 else { continue }
            let sentence = String(type.suffix(3))
            guard ["RMC", "GGA", "GLL"].contains(sentence), fields.count > (sentence == "GLL" ? 5 : 1) else { continue }
            let timeField = sentence == "GLL" ? fields[5] : fields[1]
            guard var seconds = Self.utcSeconds(timeField) else { continue }
            // Midnight rollover.
            if lastSeconds >= 0, seconds + dayOffset < lastSeconds - 43200 { dayOffset += 86400 }
            seconds += dayOffset
            lastSeconds = seconds
            var fix = fixes[seconds] ?? Fix(seconds: seconds)
            guard Self.apply(sentence: sentence, fields: fields, to: &fix) else { continue }
            if sentence == "RMC", date == nil, fields.count > 9, let d = Self.date(fields[9], time: timeField) {
                date = d
            }
            if fixes[seconds] == nil { order.append(seconds) }
            fixes[seconds] = fix
        }
        let sorted = order.sorted().compactMap { fixes[$0] }.filter { $0.latitude != nil && $0.longitude != nil }
        guard let first = sorted.first else { throw ImportError.noData }
        let times = sorted.map { $0.seconds - first.seconds }
        var columns: [RawColumn] = [
            RawColumn(name: "Latitude", unit: .degrees, suggestedRole: .latitude, values: sorted.map(\.latitude)),
            RawColumn(name: "Longitude", unit: .degrees, suggestedRole: .longitude, values: sorted.map(\.longitude)),
        ]
        func add(_ name: String, _ unit: TelemetryUnit, _ role: ChannelRole, _ values: [Double?], step: Bool = false) {
            guard values.contains(where: { $0 != nil }) else { return }
            columns.append(
                RawColumn(
                    name: name, unit: unit, suggestedRole: role, interpolation: step ? .step : .linear, values: values))
        }
        add("Speed", .metersPerSecond, .speed, sorted.map(\.speed))
        add("Course", .degrees, .heading, sorted.map(\.course))
        add("Altitude", .meters, .altitude, sorted.map(\.altitude))
        add("Satellites", .count, .aux("Satellites"), sorted.map(\.satellites), step: true)
        add("Fix quality", .count, .aux("Fix quality"), sorted.map(\.fixQuality), step: true)
        add("HDOP", .custom("DOP"), .aux("HDOP"), sorted.map(\.hdop))
        var info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        info.createdAt = date
        return RawTable(info: info, times: times, columns: columns)
    }

    /// Fills `fix` from one sentence's fields. Returns false when the sentence is void or malformed.
    static func apply(sentence: String, fields: [String], to fix: inout Fix) -> Bool {
        switch sentence {
        case "RMC":
            guard fields.count > 9, fields[2] == "A" else { return false }
            fix.latitude = coordinate(fields[3], hemisphere: fields[4])
            fix.longitude = coordinate(fields[5], hemisphere: fields[6])
            fix.speed = Double(fields[7]).map { $0 * 0.514_444 }
            fix.course = Double(fields[8])
        case "GGA":
            guard fields.count > 9 else { return false }
            fix.latitude = coordinate(fields[2], hemisphere: fields[3]) ?? fix.latitude
            fix.longitude = coordinate(fields[4], hemisphere: fields[5]) ?? fix.longitude
            fix.fixQuality = Double(fields[6])
            fix.satellites = Double(fields[7])
            fix.hdop = Double(fields[8])
            fix.altitude = Double(fields[9])
        case "GLL":
            guard fields.count > 6, fields[6] == "A" else { return false }
            fix.latitude = coordinate(fields[1], hemisphere: fields[2]) ?? fix.latitude
            fix.longitude = coordinate(fields[3], hemisphere: fields[4]) ?? fix.longitude
        default:
            return false
        }
        return true
    }

    /// `hhmmss.sss` → seconds since midnight UTC.
    static func utcSeconds(_ field: String) -> Double? {
        guard field.count >= 6, let whole = Double(field) else { return nil }
        let hh = floor(whole / 10000)
        let mm = floor((whole - hh * 10000) / 100)
        let ss = whole - hh * 10000 - mm * 100
        return hh * 3600 + mm * 60 + ss
    }

    /// `ddmm.mmmm` / `dddmm.mmmm` with N/S/E/W → signed decimal degrees.
    static func coordinate(_ field: String, hemisphere: String) -> Double? {
        guard let value = Double(field), field.count >= 4 else { return nil }
        let degrees = floor(value / 100)
        let minutes = value - degrees * 100
        var result = degrees + minutes / 60
        if hemisphere == "S" || hemisphere == "W" { result = -result }
        return result
    }

    /// RMC date `ddmmyy` + time `hhmmss.ss` → Date (UTC).
    static func date(_ dateField: String, time: String) -> Date? {
        guard dateField.count == 6, let dd = Int(dateField.prefix(2)), let mm = Int(dateField.dropFirst(2).prefix(2)),
            let yy = Int(dateField.suffix(2)), let seconds = utcSeconds(time)
        else { return nil }
        var components = DateComponents()
        components.year = 2000 + yy
        components.month = mm
        components.day = dd
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components)?.addingTimeInterval(seconds)
    }
}
