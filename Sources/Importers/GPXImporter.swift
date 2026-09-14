import Foundation
import TelemetryKit

/// Reads GPX 1.0/1.1 track files. Track points supply position, elevation and time; common
/// extensions (speed, course, heart rate, cadence, power, temperature) become channels.
/// Speed and heading are derived from position when absent.
public struct GPXImporter: TelemetryImporter {
    public static let id = "gpx"
    public static let displayName = "GPX"
    public static let fileExtensions = ["gpx"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        if sniff.head.contains("<gpx") { return .certain }
        return fileExtensions.contains(sniff.fileExtension) ? .possible : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        let data = try Data(contentsOf: url)
        let parser = GPXParser(data: data)
        let points = try parser.parse()
        guard !points.isEmpty else { throw ImportError.noData }

        // Time axis: seconds relative to the first timestamped point. Points without a
        // timestamp are dropped; duplicate times are dropped.
        guard let origin = points.first(where: { $0.time != nil })?.time else {
            throw ImportError.malformed("no track points carry a <time> element")
        }
        var times: [Double] = []
        var kept: [GPXParser.Point] = []
        for point in points {
            guard let time = point.time else { continue }
            let seconds = time.timeIntervalSince(origin)
            if let last = times.last, seconds <= last { continue }
            times.append(seconds)
            kept.append(point)
        }
        guard !times.isEmpty else { throw ImportError.noData }

        var columns: [RawColumn] = [
            RawColumn(name: "Latitude", unit: .degrees, suggestedRole: .latitude, values: kept.map { $0.latitude }),
            RawColumn(name: "Longitude", unit: .degrees, suggestedRole: .longitude, values: kept.map { $0.longitude }),
        ]
        if kept.contains(where: { $0.elevation != nil }) {
            columns.append(
                RawColumn(name: "Elevation", unit: .meters, suggestedRole: .altitude, values: kept.map { $0.elevation })
            )
        }
        let extensionKeys = Set(kept.flatMap { $0.extensions.keys })
        for key in extensionKeys.sorted() {
            let mapping = Self.mapping(forExtension: key)
            columns.append(
                RawColumn(
                    name: key, unit: mapping.unit, source: "extension", suggestedRole: mapping.role,
                    values: kept.map { $0.extensions[key] }))
        }

        var info = SessionInfo(sourceFormat: Self.displayName, sourceFileName: url.lastPathComponent)
        info.title = parser.trackName
        info.createdAt = origin
        return RawTable(info: info, times: times, columns: columns)
    }

    static func mapping(forExtension key: String) -> (role: ChannelRole, unit: TelemetryUnit) {
        switch key.lowercased() {
        case "speed": (.speed, .metersPerSecond)
        case "course", "heading", "bearing": (.heading, .degrees)
        case "hr", "heartrate": (.aux("Heart rate"), .custom("bpm"))
        case "cad", "cadence": (.aux("Cadence"), .rpm)
        case "power": (.aux("Power"), .custom("W"))
        case "atemp", "temp": (.aux("Temperature"), .celsius)
        default: (.aux(key), .none)
        }
    }
}

/// SAX-style GPX parser collecting track points in document order.
final class GPXParser: NSObject, XMLParserDelegate {
    struct Point {
        var latitude: Double
        var longitude: Double
        var elevation: Double?
        var time: Date?
        var extensions: [String: Double] = [:]
    }

    private let data: Data
    private var points: [Point] = []
    private var current: Point?
    private var text = ""
    private var elementStack: [String] = []
    private var parseError: Error?
    private(set) var trackName: String?

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let plainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [Point] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw ImportError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        return points
    }

    func date(from text: String) -> Date? {
        dateFormatter.date(from: text) ?? plainDateFormatter.date(from: text)
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        elementStack.append(elementName)
        text = ""
        if elementName == "trkpt", let lat = attributes["lat"].flatMap(Double.init),
            let lon = attributes["lon"].flatMap(Double.init)
        {
            current = Point(latitude: lat, longitude: lon)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { elementStack.removeLast() }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "trkpt" {
            if let point = current { points.append(point) }
            current = nil
            return
        }
        if elementName == "name", elementStack.dropLast().last == "trk", trackName == nil {
            trackName = value
            return
        }
        guard current != nil else { return }
        switch elementName {
        case "ele": current?.elevation = Double(value)
        case "time": current?.time = date(from: value)
        default:
            // Any leaf inside <extensions> with a numeric value becomes a channel.
            if elementStack.contains("extensions"), let number = Double(value) {
                current?.extensions[elementName] = number
            }
        }
    }
}
