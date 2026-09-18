import Foundation
import TelemetryKit

/// Reads Garmin Training Center XML (TCX): trackpoints with time, position, altitude, distance,
/// heart rate, cadence and extension speed/power. Each `<Lap>` becomes a lap.
public struct TCXImporter: TelemetryImporter {
    public static let id = "tcx"
    public static let displayName = "TCX"
    public static let fileExtensions = ["tcx"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        if sniff.head.contains("TrainingCenterDatabase") { return .certain }
        return fileExtensions.contains(sniff.fileExtension) ? .possible : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        let parser = TCXParser(data: try Data(contentsOf: url))
        let (points, lapStarts) = try parser.parse()
        guard let origin = points.first(where: { $0.time != nil })?.time else { throw ImportError.noData }
        var times: [Double] = []
        var kept: [TCXParser.Point] = []
        for point in points {
            guard let time = point.time else { continue }
            let seconds = time.timeIntervalSince(origin)
            if let last = times.last, seconds <= last { continue }
            times.append(seconds)
            kept.append(point)
        }
        guard !times.isEmpty else { throw ImportError.noData }
        var columns: [RawColumn] = []
        func add(_ name: String, _ unit: TelemetryUnit, _ role: ChannelRole?, _ values: [Double?], step: Bool = false) {
            guard values.contains(where: { $0 != nil }) else { return }
            columns.append(
                RawColumn(
                    name: name, unit: unit, suggestedRole: role, interpolation: step ? .step : .linear, values: values))
        }
        add("Latitude", .degrees, .latitude, kept.map(\.latitude))
        add("Longitude", .degrees, .longitude, kept.map(\.longitude))
        add("Altitude", .meters, .altitude, kept.map(\.altitude))
        add("Distance", .meters, .distance, kept.map(\.distance))
        add("Speed", .metersPerSecond, .speed, kept.map(\.speed))
        add("Heart rate", .custom("bpm"), .aux("Heart rate"), kept.map(\.heartRate))
        add("Cadence", .rpm, .aux("Cadence"), kept.map(\.cadence))
        add("Power", .custom("W"), .aux("Power"), kept.map(\.power))
        let markers = lapStarts.indices.compactMap { index -> RawLapMarker? in
            // TCX laps list their start; the end of lap N is the start of lap N+1.
            guard index + 1 < lapStarts.count else { return nil }
            return RawLapMarker(number: index, time: lapStarts[index + 1].timeIntervalSince(origin))
        }
        var info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        info.createdAt = origin
        info.title = parser.activitySport
        return RawTable(info: info, times: times, columns: columns, lapMarkers: markers)
    }
}

final class TCXParser: NSObject, XMLParserDelegate {
    struct Point {
        var time: Date?
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var distance: Double?
        var speed: Double?
        var heartRate: Double?
        var cadence: Double?
        var power: Double?
    }

    private let data: Data
    private var points: [Point] = []
    private var lapStarts: [Date] = []
    private var current: Point?
    private var stack: [String] = []
    private var text = ""
    private(set) var activitySport: String?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let plainFormatter = ISO8601DateFormatter()

    init(data: Data) { self.data = data }

    func parse() throws -> ([Point], [Date]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw ImportError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        return (points, lapStarts)
    }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        stack.append(name)
        text = ""
        switch name {
        case "Trackpoint": current = Point()
        case "Lap":
            if let start = attributes["StartTime"].flatMap({
                dateFormatter.date(from: $0) ?? plainFormatter.date(from: $0)
            }) {
                lapStarts.append(start)
            }
        case "Activity": activitySport = attributes["Sport"]
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { stack.removeLast() }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "Trackpoint" {
            if let point = current { points.append(point) }
            current = nil
            return
        }
        guard current != nil else { return }
        let number = Double(value)
        switch name {
        case "Time": current?.time = dateFormatter.date(from: value) ?? plainFormatter.date(from: value)
        case "LatitudeDegrees": current?.latitude = number
        case "LongitudeDegrees": current?.longitude = number
        case "AltitudeMeters": current?.altitude = number
        case "DistanceMeters": current?.distance = number
        case "Speed": current?.speed = number
        case "Value" where stack.dropLast().last == "HeartRateBpm": current?.heartRate = number
        case "Cadence", "RunCadence": current?.cadence = number
        case "Watts": current?.power = number
        default: break
        }
    }
}
