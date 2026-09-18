import Foundation
import TelemetryKit

/// DJI flight/recording logs written as `.SRT` subtitle files next to the video (drones, Osmo
/// Action, Avata): one cue per frame with GPS, altitude, speed and camera settings. Times are
/// the cue times, i.e. seconds from the start of the video, and the first cue's date anchors the
/// log to the clock.
public struct DJISRTImporter: TelemetryImporter {
    public static let id = "dji-srt"
    public static let displayName = "DJI SRT"
    public static let fileExtensions = ["srt"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        guard sniff.head.contains("-->") else { return .no }
        let head = sniff.head.lowercased()
        if head.contains("latitude") || head.contains("gps(") || head.contains("gps (") { return .certain }
        return sniff.fileExtension == "srt" ? .possible : .no
    }

    struct Cue {
        var seconds: Double
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var height: Double?
        var speed: Double?
        var distance: Double?
        var iso: Double?
        var shutter: Double?
        var aperture: Double?
        var date: Date?
    }

    public func importFile(at url: URL) throws -> RawTable {
        let text = try CSVReader.loadText(from: url)
        var cues: [Cue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let timing = lines.first(where: { $0.contains("-->") }),
                let seconds = Self.cueStart(timing)
            else { continue }
            var cue = Cue(seconds: seconds)
            let body = lines.filter { !$0.contains("-->") }.joined(separator: " ")
            Self.parse(body, into: &cue)
            guard cue.latitude != nil || cue.longitude != nil || cue.height != nil || cue.speed != nil else {
                continue
            }
            cues.append(cue)
        }
        guard !cues.isEmpty else { throw ImportError.noData }
        // Cues repeat at frame rate but the values usually change less often; keep one per cue anyway.
        var info = SessionInfo(sourceFormat: Self.displayName)
        if let first = cues.first(where: { $0.date != nil }), let date = first.date {
            info.createdAt = date.addingTimeInterval(-first.seconds)
        }
        var columns: [RawColumn] = []
        func add(_ name: String, _ unit: TelemetryUnit, _ role: ChannelRole, _ values: [Double?]) {
            guard values.contains(where: { $0 != nil }) else { return }
            columns.append(RawColumn(name: name, unit: unit, suggestedRole: role, values: values))
        }
        add("Latitude", .degrees, .latitude, cues.map(\.latitude))
        add("Longitude", .degrees, .longitude, cues.map(\.longitude))
        add("Altitude", .meters, .altitude, cues.map(\.altitude))
        add("Height", .meters, .aux("Height"), cues.map(\.height))
        add("Speed", .metersPerSecond, .speed, cues.map(\.speed))
        add("Distance", .meters, .aux("Home distance"), cues.map(\.distance))
        add("ISO", .count, .aux("ISO"), cues.map(\.iso))
        add("Shutter", .custom("1/s"), .aux("Shutter"), cues.map(\.shutter))
        add("Aperture", .custom("f"), .aux("Aperture"), cues.map(\.aperture))
        return RawTable(info: info, times: cues.map(\.seconds), columns: columns)
    }

    // MARK: - Parsing

    /// `00:01:02,345 --> 00:01:02,378` → 62.345.
    static func cueStart(_ line: String) -> Double? {
        guard let start = line.components(separatedBy: "-->").first?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        let parts = start.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else {
            return nil
        }
        return h * 3600 + m * 60 + s
    }

    nonisolated(unsafe) private static let patterns: [(String, NSRegularExpression)] = {
        func rx(_ p: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
        }
        return [
            ("latitude", rx(#"latitude\s*[:=]\s*(-?\d+(?:\.\d+)?)"#)),
            ("longitude", rx(#"longitude\s*[:=]\s*(-?\d+(?:\.\d+)?)"#)),
            // GPS(lon, lat, alt) — DJI writes longitude first.
            ("gps", rx(#"GPS\s*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:\s*,\s*(-?\d+(?:\.\d+)?))?\s*\)"#)),
            ("rel_alt", rx(#"rel_alt\s*[:=]\s*(-?\d+(?:\.\d+)?)"#)),
            ("abs_alt", rx(#"abs_alt\s*[:=]\s*(-?\d+(?:\.\d+)?)"#)),
            ("height", rx(#"(?:^|[\s,])H\s+(-?\d+(?:\.\d+)?)\s*m(?![/\w])"#)),
            ("hspeed", rx(#"H\.S\s+(-?\d+(?:\.\d+)?)\s*m/s"#)),
            ("distance", rx(#"(?:^|[\s,])D\s+(-?\d+(?:\.\d+)?)\s*m(?![/\w])"#)),
            ("barometer", rx(#"BAROMETER\s*[:=]\s*(-?\d+(?:\.\d+)?)"#)),
            ("iso", rx(#"iso\s*[:=]?\s*(\d+)"#)),
            ("shutter", rx(#"(?:shutter\s*[:=]\s*1/|SS\s+)(\d+(?:\.\d+)?)"#)),
            ("fnum", rx(#"(?:fnum\s*[:=]\s*|F/)(\d+(?:\.\d+)?)"#)),
            ("date", rx(#"(\d{4})[-./](\d{2})[-./](\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:[.,](\d{1,3}))?"#)),
        ]
    }()

    static func parse(_ body: String, into cue: inout Cue) {
        let range = NSRange(body.startIndex..., in: body)
        func value(_ match: NSTextCheckingResult, _ group: Int) -> Double? {
            guard group < match.numberOfRanges, let r = Range(match.range(at: group), in: body) else { return nil }
            return Double(body[r])
        }
        for (name, regex) in patterns {
            guard let match = regex.firstMatch(in: body, range: range) else { continue }
            switch name {
            case "latitude": cue.latitude = value(match, 1)
            case "longitude": cue.longitude = value(match, 1)
            case "gps":
                if cue.longitude == nil { cue.longitude = value(match, 1) }
                if cue.latitude == nil { cue.latitude = value(match, 2) }
                if cue.altitude == nil { cue.altitude = value(match, 3) }
            case "rel_alt": cue.height = value(match, 1)
            case "abs_alt": cue.altitude = value(match, 1)
            case "height": if cue.height == nil { cue.height = value(match, 1) }
            case "hspeed": cue.speed = value(match, 1)
            case "distance": cue.distance = value(match, 1)
            case "barometer": if cue.height == nil { cue.height = value(match, 1) }
            case "iso": cue.iso = value(match, 1)
            case "shutter": cue.shutter = value(match, 1)
            case "fnum": cue.aperture = value(match, 1)
            case "date": cue.date = date(from: match, in: body)
            default: break
            }
        }
    }

    private static func date(from match: NSTextCheckingResult, in body: String) -> Date? {
        func int(_ group: Int) -> Int? {
            guard group < match.numberOfRanges, let r = Range(match.range(at: group), in: body) else { return nil }
            return Int(body[r])
        }
        guard let y = int(1), let mo = int(2), let d = int(3), let h = int(4), let mi = int(5), let s = int(6) else {
            return nil
        }
        var components = DateComponents()
        components.year = y
        components.month = mo
        components.day = d
        components.hour = h
        components.minute = mi
        components.second = s
        var calendar = Calendar(identifier: .gregorian)
        // DJI writes the camera's local time without a zone; treat it as the machine's zone.
        calendar.timeZone = .current
        guard var date = calendar.date(from: components) else { return nil }
        if let fraction = match.range(at: 7).location != NSNotFound ? Range(match.range(at: 7), in: body) : nil {
            let digits = body[fraction]
            date.addTimeInterval((Double(digits) ?? 0) / pow(10, Double(digits.count)))
        }
        return date
    }
}
