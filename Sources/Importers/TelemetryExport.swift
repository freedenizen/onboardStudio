import Foundation
import TelemetryKit

/// Telemetry out again (#563): a session, or one lap of it, written in an open format another tool
/// reads — every channel as CSV, the path as GPX or KML, or Racelogic's VBO. What is written is the
/// session as the app reads it, so a trim, a split or a start/finish line set here goes with it.
public enum TelemetryExport {
    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case csv, gpx, kml, vbo

        public var id: String { rawValue }
        public var fileExtension: String { rawValue }

        public var title: String {
            switch self {
            case .csv: "CSV — every channel"
            case .gpx: "GPX — the path, for maps and fitness apps"
            case .kml: "KML — the path, for Google Earth"
            case .vbo: "VBO — Racelogic Circuit Tools and other lap timers"
            }
        }

        /// Whether the format can say anything without positions.
        public var needsPosition: Bool { self != .csv }
    }

    /// What to write: the whole session, or one lap.
    public enum Scope: Hashable, Sendable {
        case session
        case lap(Int)
    }

    public enum Failure: LocalizedError, Equatable {
        case noPosition
        case noSuchLap(Int)
        case nothingToWrite

        public var errorDescription: String? {
            switch self {
            case .noPosition:
                "This session has no GPS positions, so there is no path to write. CSV writes every channel."
            case .noSuchLap(let number): "The session has no complete lap \(number)."
            case .nothingToWrite: "The session has no samples to write."
            }
        }
    }

    /// `session` (or the scope of it) as `format`, named `name` inside the file where it has a name.
    public static func export(
        _ session: TelemetrySession, as format: Format, scope: Scope = .session, name: String = "Session"
    ) throws -> Data {
        let span = try span(of: session, scope: scope)
        if format.needsPosition, !session.hasPosition { throw Failure.noPosition }
        let text =
            switch format {
            case .csv: try csv(session, span: span)
            case .gpx: try gpx(session, span: span, name: name)
            case .kml: try kml(session, span: span, name: name)
            case .vbo: try vbo(session, span: span)
            }
        return Data(text.utf8)
    }

    /// The session times to write.
    static func span(of session: TelemetrySession, scope: Scope) throws -> ClosedRange<Double> {
        switch scope {
        case .session:
            guard let range = session.timeRange else { throw Failure.nothingToWrite }
            return range
        case .lap(let number):
            guard let lap = session.laps.first(where: { $0.number == number }), let end = lap.end else {
                throw Failure.noSuchLap(number)
            }
            return lap.start...end
        }
    }

    /// Every time any of `channels` has a sample within `span`, once each, in order: every value the
    /// file has is written as it was, the others read between their own samples.
    static func times(of channels: [Channel], in span: ClosedRange<Double>) -> [Double] {
        Array(Set(channels.flatMap { $0.times.filter { span.contains($0) } })).sorted()
    }

    /// What the app works out from the laps — deltas to the best lap, the projected time, the GPS
    /// rate, grip used — is the app's reading, not the drive, and another tool works out its own.
    static let derivedRoles: Set<ChannelRole> = [.lapDelta, .speedDelta, .projectedLap, .gpsRate]

    /// The channels a CSV carries, each under a name no other column has.
    static func columns(of session: TelemetrySession) -> [(name: String, channel: Channel)] {
        var used: Set<String> = []
        return session.orderedChannels.filter { !derivedRoles.contains($0.role) }.map { channel in
            let unit = channel.unit.symbol
            var name = unit.isEmpty ? channel.name : "\(channel.name) (\(unit))"
            if used.contains(name.lowercased()) {
                name =
                    unit.isEmpty
                    ? "\(channel.name) [\(channel.role.identifier)]"
                    : "\(channel.name) [\(channel.role.identifier)] (\(unit))"
            }
            used.insert(name.lowercased())
            return (name, channel)
        }
    }

    /// The lap a time falls in, 0 outside every lap.
    static func lapNumber(at time: Double, in session: TelemetrySession) -> Int {
        session.laps.last { $0.start <= time && ($0.end ?? .infinity) > time }?.number ?? 0
    }

    // MARK: - CSV

    static func csv(_ session: TelemetrySession, span: ClosedRange<Double>) throws -> String {
        let columns = columns(of: session)
        let channels = columns.map(\.channel)
        let times = times(of: channels, in: span)
        guard !times.isEmpty else { throw Failure.nothingToWrite }
        let utc = session.hasAbsoluteTime
        var header = ["time (s)"] + (utc ? ["utc"] : []) + ["lap"]
        header += columns.map { quoted($0.name) }
        var lines = [header.joined(separator: ",")]
        lines.reserveCapacity(times.count + 1)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for time in times {
            var fields = [number(time - span.lowerBound, 3)]
            if utc {
                fields.append(
                    session.epoch(forSessionTime: time).map { iso.string(from: Date(timeIntervalSince1970: $0)) } ?? "")
            }
            fields.append(String(lapNumber(at: time, in: session)))
            fields += channels.map { channel in channel.value(at: time).map { number($0, 7) } ?? "" }
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quoted(_ text: String) -> String {
        text.contains(",") || text.contains("\"")
            ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
    }

    /// Up to `decimals` places, without trailing zeros.
    static func number(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "" }
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    // MARK: - Positions

    struct Fix {
        let time: Double
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let speed: Double?
        let heading: Double?
    }

    /// Every position in `span`, one per position sample.
    static func fixes(of session: TelemetrySession, in span: ClosedRange<Double>) -> [Fix] {
        guard let latitude = session[.latitude], let longitude = session[.longitude] else { return [] }
        let speed = session[.speed]
        let altitude = session[.altitude]
        let heading = session[.heading]
        return zip(latitude.times, latitude.values).compactMap { time, lat in
            guard span.contains(time), lat.isFinite, let lon = longitude.value(at: time), lon.isFinite else {
                return nil
            }
            // Speed in m/s whatever the file logged.
            let metresPerSecond = speed.flatMap { channel in
                channel.value(at: time).flatMap { channel.unit.convert($0, to: .metersPerSecond) }
            }
            return Fix(
                time: time, latitude: lat, longitude: lon, altitude: altitude?.value(at: time), speed: metresPerSecond,
                heading: heading?.value(at: time))
        }
    }

    /// The fixes grouped by lap, in order; the stretch before the first lap and after the last is
    /// a group of its own.
    static func byLap(_ fixes: [Fix], in session: TelemetrySession) -> [(lap: Int, fixes: [Fix])] {
        var groups: [(lap: Int, fixes: [Fix])] = []
        for fix in fixes {
            let lap = lapNumber(at: fix.time, in: session)
            if groups.last?.lap == lap {
                groups[groups.count - 1].fixes.append(fix)
            } else {
                groups.append((lap, [fix]))
            }
        }
        return groups
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
