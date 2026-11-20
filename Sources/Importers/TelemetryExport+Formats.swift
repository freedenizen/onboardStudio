import Foundation
import TelemetryKit

/// The path formats: GPX, KML and VBO (#563).
extension TelemetryExport {
    // MARK: - GPX

    static func gpx(_ session: TelemetrySession, span: ClosedRange<Double>, name: String) throws -> String {
        let fixes = fixes(of: session, in: span)
        guard !fixes.isEmpty else { throw Failure.noPosition }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Onboard Studio" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <trk>", "    <name>\(escaped(name))</name>",
        ]
        for group in byLap(fixes, in: session) {
            lines.append("    <trkseg>")
            for fix in group.fixes {
                var point = #"      <trkpt lat="\#(number(fix.latitude, 8))" lon="\#(number(fix.longitude, 8))">"#
                if let altitude = fix.altitude, altitude.isFinite { point += "<ele>\(number(altitude, 2))</ele>" }
                if let epoch = session.epoch(forSessionTime: fix.time) {
                    point += "<time>\(iso.string(from: Date(timeIntervalSince1970: epoch)))</time>"
                }
                if let speed = fix.speed, speed.isFinite {
                    point += "<extensions><speed>\(number(speed, 3))</speed></extensions>"
                }
                lines.append(point + "</trkpt>")
            }
            lines.append("    </trkseg>")
        }
        lines += ["  </trk>", "</gpx>"]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - KML

    static func kml(_ session: TelemetrySession, span: ClosedRange<Double>, name: String) throws -> String {
        let fixes = fixes(of: session, in: span)
        guard !fixes.isEmpty else { throw Failure.noPosition }
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#, #"<kml xmlns="http://www.opengis.net/kml/2.2">"#,
            "  <Document>", "    <name>\(escaped(name))</name>",
            #"    <Style id="lap"><LineStyle><color>ff0080ff</color><width>3</width></LineStyle></Style>"#,
        ]
        for group in byLap(fixes, in: session) {
            let title = group.lap == 0 ? "Before and after the laps" : "Lap \(group.lap)"
            let coordinates = group.fixes.map { fix in
                "\(number(fix.longitude, 8)),\(number(fix.latitude, 8)),\(number(fix.altitude ?? 0, 2))"
            }
            lines += [
                "    <Placemark>", "      <name>\(title)</name>", "      <styleUrl>#lap</styleUrl>",
                "      <LineString><tessellate>1</tessellate><altitudeMode>clampToGround</altitudeMode>",
                "        <coordinates>\(coordinates.joined(separator: " "))</coordinates>",
                "      </LineString>", "    </Placemark>",
            ]
        }
        lines += ["  </Document>", "</kml>"]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - VBO

    /// Racelogic's text format: positions in minutes with west positive, time as UTC `hhmmss.ss`,
    /// speed in km/h, and the start/finish line in `[laptiming]` when the session knows it.
    static func vbo(_ session: TelemetrySession, span: ClosedRange<Double>) throws -> String {
        let fixes = fixes(of: session, in: span)
        guard !fixes.isEmpty else { throw Failure.noPosition }
        let start = session.epoch(forSessionTime: span.lowerBound)
        let created = Date(timeIntervalSince1970: start ?? 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = calendar.dateComponents([.day, .month, .year, .hour, .minute, .second], from: created)
        let lateral = session[.lateralG]
        let longitudinal = session[.longitudinalG]
        var header = ["sats", "time", "lat", "long", "velocity kmh", "heading", "height"]
        var names = ["sats", "time", "lat", "long", "velocity", "heading", "height"]
        if longitudinal != nil {
            header.append("longacc")
            names.append("longacc")
        }
        if lateral != nil {
            header.append("latacc")
            names.append("latacc")
        }
        // The day it was driven, when the file knows it; without the file's clock, no made-up date.
        var lines: [String] = []
        if start != nil {
            lines.append(
                String(
                    format: "File created on %02d/%02d/%04d at %02d:%02d:%02d", day.day ?? 1, day.month ?? 1,
                    day.year ?? 1970, day.hour ?? 0, day.minute ?? 0, day.second ?? 0))
            lines.append("")
        }
        lines.append("[header]")
        lines += header
        if let gate = session.lapGeometry.start {
            lines += [
                "", "[laptiming]",
                "Start \(signed(-gate.startLongitude * 60)) \(signed(gate.startLatitude * 60)) "
                    + "\(signed(-gate.endLongitude * 60)) \(signed(gate.endLatitude * 60)) ¬ \(gate.label)",
            ]
        }
        lines += ["", "[column names]", names.joined(separator: " "), "", "[data]"]
        for fix in fixes {
            // Time of day by the file's clock; without one, from midnight.
            let seconds = (session.epoch(forSessionTime: fix.time) ?? fix.time).truncatingRemainder(dividingBy: 86_400)
            let hh = Int(seconds / 3600)
            let mm = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            let ss = seconds.truncatingRemainder(dividingBy: 60)
            var row = [
                "008", String(format: "%02d%02d%05.2f", hh, mm, ss), signed(fix.latitude * 60),
                signed(-fix.longitude * 60), String(format: "%.3f", (fix.speed ?? 0) * 3.6),
                String(format: "%.2f", fix.heading ?? 0), signed(fix.altitude ?? 0, 2),
            ]
            if let longitudinal { row.append(signed(longitudinal.value(at: fix.time) ?? 0, 3)) }
            if let lateral { row.append(signed(lateral.value(at: fix.time) ?? 0, 3)) }
            lines.append(row.joined(separator: " "))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func signed(_ value: Double, _ decimals: Int = 6) -> String {
        String(format: "%+.\(decimals)f", value.isFinite ? value : 0)
    }
}
