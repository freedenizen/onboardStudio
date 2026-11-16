import Foundation
import TelemetryKit
import Testing

@testable import Importers

/// #563: a session written out in an open format reads back in as the same drive.
@Suite("Telemetry export (#563)")
struct TelemetryExportTests {
    static func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(path: name)
    }

    static func text(_ data: Data) throws -> String { try #require(String(bytes: data, encoding: .utf8)) }

    /// `session` written as `format` to a temporary file, and that file read back in.
    static func roundTrip(
        _ session: TelemetrySession, as format: TelemetryExport.Format, scope: TelemetryExport.Scope = .session
    ) throws -> TelemetrySession {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "export-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try TelemetryExport.export(session, as: format, scope: scope).write(to: url)
        return try FormatDetector.importSession(at: url)
    }

    static func positionsMatch(_ a: TelemetrySession, _ b: TelemetrySession, tolerance: Double = 1e-5) throws {
        let latitude = try #require(a[.latitude])
        let back = try #require(b[.latitude])
        #expect(back.count == latitude.count)
        for (x, y) in zip(latitude.values, back.values).prefix(200) { #expect(abs(x - y) < tolerance) }
        let longitude = try #require(b[.longitude])
        for (x, y) in zip(try #require(a[.longitude]).values, longitude.values).prefix(200) {
            #expect(abs(x - y) < tolerance)
        }
    }

    @Test func aVBOReadsBackWithItsPositionsSpeedsAndLine() throws {
        let session = try FormatDetector.importSession(at: try Self.fixture("session.vbo"))
        let back = try Self.roundTrip(session, as: .vbo)
        try Self.positionsMatch(session, back)
        let speed = try #require(session[.speed])
        let speedBack = try #require(back[.speed])
        for (x, y) in zip(speed.values, speedBack.values).prefix(200) {
            let kmh = (speed.unit.convert(x, to: .kilometersPerHour) ?? x)
            #expect(abs(kmh - (speedBack.unit.convert(y, to: .kilometersPerHour) ?? y)) < 0.01)
        }
        #expect(back.lapGeometry.start != nil || session.lapGeometry.start == nil)
        #expect(back.laps.filter(\.isComplete).count == session.laps.filter(\.isComplete).count)
    }

    @Test func aGPXReadsBackWithItsPositionsAndTimes() throws {
        let session = try FormatDetector.importSession(at: try Self.fixture("session.vbo"))
        let back = try Self.roundTrip(session, as: .gpx)
        try Self.positionsMatch(session, back)
        #expect(abs((back.duration) - session.duration) < 0.1)
    }

    @Test func aCSVHasEveryChannelWithItsUnit() throws {
        let session = try FormatDetector.importSession(at: try Self.fixture("racechrono-v3.csv"))
        let text = try Self.text(try TelemetryExport.export(session, as: .csv))
        let lines = text.split(separator: "\n")
        let header = try #require(lines.first).split(separator: ",").map(String.init)
        #expect(header.prefix(1) == ["time (s)"] && header.contains("lap"))
        #expect(Set(header).count == header.count, "every column named once")
        #expect(!header.contains { $0.hasPrefix("Delta to best lap") }, "the app's own readings are not the drive")
        let back = try Self.roundTrip(session, as: .csv)
        // Every recorded position comes back at its own time.
        let latitude = try #require(session[.latitude])
        let start = try #require(session.timeRange).lowerBound
        let backLatitude = try #require(back[.latitude])
        let offset = try #require(back.timeRange).lowerBound
        for (time, value) in zip(latitude.times, latitude.values) {
            #expect(abs((backLatitude.value(at: time - start + offset) ?? 0) - value) < 1e-6)
        }
    }

    @Test func oneLapIsJustThatLap() throws {
        let session = try FormatDetector.importSession(at: try Self.fixture("coaching-laps.csv"))
        let lap = try #require(session.laps.first { $0.isComplete })
        let back = try Self.roundTrip(session, as: .vbo, scope: .lap(lap.number))
        let duration = try #require(lap.duration)
        #expect(abs(back.duration - duration) < 0.5)
        // Without the file's clock a VBO and a GPX say where, not when: no made-up date.
        let vbo = try Self.text(try TelemetryExport.export(session, as: .vbo))
        #expect(!vbo.contains("File created on") && vbo.hasPrefix("[header]"))
        #expect(back.info.createdAt == nil)
        let gpx = try Self.text(try TelemetryExport.export(session, as: .gpx))
        #expect(!session.hasAbsoluteTime && !gpx.contains("<time>") && gpx.contains("<trkpt"))
        #expect(throws: TelemetryExport.Failure.noSuchLap(999)) {
            try TelemetryExport.export(session, as: .csv, scope: .lap(999))
        }
    }

    @Test func aKMLHasALinePerLap() throws {
        let session = try FormatDetector.importSession(at: try Self.fixture("session.vbo"))
        let text = try Self.text(try TelemetryExport.export(session, as: .kml, name: "Sonoma & more"))
        let laps = Set(session.laps.map(\.number))
        #expect(text.components(separatedBy: "<Placemark>").count - 1 >= laps.count)
        #expect(text.contains("<name>Sonoma &amp; more</name>"))
        #expect(text.contains("<coordinates>"))
    }

    @Test func noPositionsIsCSVOnly() throws {
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2],
            columns: [RawColumn(name: "rpm", unit: .rpm, suggestedRole: .rpm, values: [1, 2, 3])])
        let session = SessionBuilder.build(table)
        #expect(throws: TelemetryExport.Failure.noPosition) { try TelemetryExport.export(session, as: .gpx) }
        #expect((try? TelemetryExport.export(session, as: .csv)) != nil)
    }
}
