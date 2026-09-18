import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        let base = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return base.appending(path: name)
    }
}

@Suite("CSVReader")
struct CSVReaderTests {
    @Test func splitsQuotedFieldsAndEscapedQuotes() {
        let reader = CSVReader(delimiter: .comma)
        #expect(reader.fields(of: #"a,"b,c","d""e",,f"#) == ["a", "b,c", "d\"e", "", "f"])
    }

    @Test func detectsDelimiter() {
        #expect(CSVReader.detectDelimiter(in: "a;b;c\n1;2;3\n") == .semicolon)
        #expect(CSVReader.detectDelimiter(in: "a\tb\tc\n1\t2\t3\n") == .tab)
        #expect(CSVReader.detectDelimiter(in: "a,b,c\n1,2,3\n") == .comma)
    }

    @Test func handlesLineEndingsAndTrailingNewline() {
        #expect(CSVReader.lines(of: "a\r\nb\rc\nd\n").count == 4)
        #expect(CSVReader.lines(of: "a\nb").count == 2)
    }

    @Test func parsesNumbersWithEuropeanDecimal() {
        #expect(CSVReader.number("1,5") == 1.5)
        #expect(CSVReader.number(" 2.25 ") == 2.25)
        #expect(CSVReader.number("") == nil)
        #expect(CSVReader.number("abc") == nil)
    }

    @Test func stripsBOM() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "bom-\(UUID().uuidString).csv")
        try Data([0xEF, 0xBB, 0xBF] + Array("Time,MPH\n0,1\n".utf8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try CSVReader.loadText(from: url).hasPrefix("Time,"))
    }
}

@Suite("RaceRender CSV importer")
struct RaceRenderCSVImporterTests {
    @Test func detectsFormatWithCertainty() throws {
        let sniff = try FileSniff.sniff(try Fixtures.url("racerender-basic.csv"))
        #expect(RaceRenderCSVImporter.confidence(for: sniff) == .certain)
        #expect(RaceChronoCSVImporter.confidence(for: sniff) == .no)
        #expect(GPXImporter.confidence(for: sniff) == .no)
    }

    @Test func parsesTimesLapsAndColumns() throws {
        let table = try RaceRenderCSVImporter().importFile(at: try Fixtures.url("racerender-basic.csv"))
        #expect(table.rowCount == 20)
        #expect(table.times.first == 0)
        #expect(table.times.last == 9.5)
        #expect(table.lapMarkers == [RawLapMarker(number: 0, time: 4), RawLapMarker(number: 1, time: 8)])
        let mph = try #require(table.column(named: "MPH"))
        #expect(mph.suggestedRole == .speed)
        #expect(mph.unit == .milesPerHour)
        let coolant = try #require(table.column(named: "Coolant"))
        #expect(coolant.suggestedRole == .obd("Coolant"))
        #expect(coolant.source == "obd")
        #expect(table.column(named: "Time") == nil)
    }

    @Test func buildsSessionWithCanonicalUnitsAndLaps() throws {
        let session = try RaceRenderCSVImporter().importSession(at: try Fixtures.url("racerender-basic.csv"))
        let speed = try #require(session[.speed])
        #expect(speed.unit == .metersPerSecond)
        #expect(abs((speed.value(at: 1) ?? 0) - 40 * 0.44704) < 1e-6)
        #expect(session.laps.map(\.number) == [0, 1, 2])
        #expect(session.laps[1].duration == 4)
        #expect(session.laps[2].isComplete == false)
        #expect(session[.gear]?.interpolation == .step)
        #expect(session[.obd("Coolant")]?.values.first == 80)
        // Distance is derived because the file has none; speed is not re-derived.
        #expect(session[.distance]?.name == "Distance (from GPS)")
        #expect(session[.speed]?.name == "MPH")
    }

    @Test func emptyCellBecomesNilWithoutAffectingOtherColumns() throws {
        // Row at t=9.0 in the fixture has an empty MPH cell.
        let table = try RaceRenderCSVImporter().importFile(at: try Fixtures.url("racerender-basic.csv"))
        let index = try #require(table.times.firstIndex(of: 9.0))
        let mph = try #require(table.column(named: "MPH"))
        #expect(mph.values[index] == nil)
        #expect(table.column(named: "Lap")?.values[index] == 2)
        #expect(table.column(named: "Heading")?.values[index] == 180)
        let session = SessionBuilder.build(table)
        #expect(session[.speed]?.count == 19)
    }

    @Test func lapMarkerParsing() {
        #expect(RaceRenderCSVImporter.lapMarker(from: "# Lap 3: 00:02:23.07") == RawLapMarker(number: 3, time: 143.07))
        #expect(RaceRenderCSVImporter.lapMarker(from: "#lap 12:  95.5") == RawLapMarker(number: 12, time: 95.5))
        #expect(RaceRenderCSVImporter.lapMarker(from: "# Comment") == nil)
        #expect(RaceRenderCSVImporter.lapMarker(from: "# Lap x: 1") == nil)
    }

    @Test func rejectsFilesWithoutTime() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notime-\(UUID().uuidString).csv")
        try "Speed,RPM\n1,2\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ImportError.missingColumn("Time")) { try RaceRenderCSVImporter().importFile(at: url) }
    }
}

@Suite("RaceChrono CSV importer")
struct RaceChronoCSVImporterTests {
    @Test func detectsFormatWithCertainty() throws {
        let sniff = try FileSniff.sniff(try Fixtures.url("racechrono-v3.csv"))
        #expect(RaceChronoCSVImporter.confidence(for: sniff) == .certain)
        #expect(RaceRenderCSVImporter.confidence(for: sniff) == .no)
    }

    @Test func parsesPreambleMetadata() throws {
        let table = try RaceChronoCSVImporter().importFile(at: try Fixtures.url("racechrono-v3.csv"))
        #expect(table.info.sourceFormat == "RaceChrono CSV")
        #expect(table.info.title == "Test Circuit")
        #expect(table.info.trackName == "Test Circuit")
        #expect(table.info.driverName == "OverlayGen")
        #expect(table.info.notes == "synthetic fixture, two laps")
        let created = try #require(table.info.createdAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: created)
        #expect(parts.year == 2025 && parts.month == 12 && parts.day == 31 && parts.hour == 2 && parts.minute == 54)
    }

    @Test func dropsDuplicateTimestampsAndKeepsUnixTime() throws {
        let table = try RaceChronoCSVImporter().importFile(at: try Fixtures.url("racechrono-v3.csv"))
        #expect(table.rowCount == 12)
        #expect(table.times.first == 1_767_150_797.0)
        #expect(zip(table.times, table.times.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func mapsColumnsUnitsAndSources() throws {
        let table = try RaceChronoCSVImporter().importFile(at: try Fixtures.url("racechrono-v3.csv"))
        let speeds = table.columns.filter { $0.name == "speed" }
        #expect(speeds.count == 3)
        #expect(speeds[0].source == "100: gps" && speeds[0].suggestedRole == .speed)
        #expect(speeds[1].source == "calc" && speeds[1].suggestedRole == .speed)
        #expect(speeds[2].source == "200: obd" && speeds[2].suggestedRole == .obd("speed"))
        #expect(table.column(named: "rpm")?.suggestedRole == .rpm)
        #expect(table.column(named: "rpm")?.values[5] == nil)  // blank OBD cell
        #expect(table.column(named: "lateral_acc")?.unit == .gForce)
        #expect(table.column(named: "bearing")?.suggestedRole == .heading)
        #expect(table.column(named: "distance_traveled")?.suggestedRole == .distance)
        #expect(table.column(named: "lap_number")?.suggestedRole == .lap)
    }

    @Test func sessionHasGpsSpeedLapsAndAuxDuplicates() throws {
        let session = try RaceChronoCSVImporter().importSession(at: try Fixtures.url("racechrono-v3.csv"))
        #expect(abs((session[.speed]?.value(at: 1_767_150_797.1) ?? 0) - 20.5) < 1e-6)
        #expect(session[.aux("speed (calc)")] != nil)
        #expect(session[.obd("speed")] != nil)
        #expect(session.laps.map(\.number) == [8, 9, 10])
        #expect(session.laps[0].isComplete == false)  // export starts mid-lap
        #expect(session.laps[1].isComplete == true)
        #expect(abs((session.laps[1].duration ?? 0) - 1.0) < 1e-6)
        #expect(session[.rpm]?.count == 11)  // one blank cell dropped
        #expect(session[.latitude] != nil && session[.longitude] != nil)
    }

    @Test func toleratesMissingUnitsAndSourceRows() throws {
        let text = """
            This file is created using RaceChrono v6.0.0 ( http://racechrono.com/ ).
            Format,2
            timestamp,lap_number,latitude,longitude,speed
            10.0,0,45.0,-122.0,1.0
            10.5,0,45.0001,-122.0,2.0
            """
        let url = FileManager.default.temporaryDirectory.appending(path: "rc2-\(UUID().uuidString).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try RaceChronoCSVImporter().importFile(at: url)
        #expect(table.rowCount == 2)
        #expect(table.column(named: "speed")?.unit == .metersPerSecond)
    }
}

@Suite("GPX importer")
struct GPXImporterTests {
    @Test func detectsFormat() throws {
        let sniff = try FileSniff.sniff(try Fixtures.url("track.gpx"))
        #expect(GPXImporter.confidence(for: sniff) == .certain)
        #expect(RaceRenderCSVImporter.confidence(for: sniff) == .no)
    }

    @Test func parsesPointsRelativeTimesElevationAndExtensions() throws {
        let table = try GPXImporter().importFile(at: try Fixtures.url("track.gpx"))
        #expect(table.rowCount == 6)  // untimed point dropped
        #expect(table.times == [0, 1, 2, 3.5, 4.5, 5.5])
        #expect(table.info.title == "Test loop")
        #expect(table.column(named: "Elevation")?.values.first == 100)
        let hr = try #require(table.column(named: "hr"))
        #expect(hr.suggestedRole == .aux("Heart rate"))
        #expect(hr.values[4] == nil)
    }

    @Test func sessionDerivesSpeedHeadingAndDistance() throws {
        let session = try GPXImporter().importSession(at: try Fixtures.url("track.gpx"))
        let speed = try #require(session[.speed])
        #expect(speed.name == "Speed (from GPS)")
        #expect(abs((speed.value(at: 0) ?? 0) - 10) < 0.2)
        #expect(session[.heading] != nil)
        #expect(session[.distance] != nil)
        #expect(session.laps.isEmpty)
    }

    @Test func rejectsInvalidXML() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "bad-\(UUID().uuidString).gpx")
        try "<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\">".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ImportError.self) { try GPXImporter().importFile(at: url) }
    }
}

@Suite("FormatDetector")
struct FormatDetectorTests {
    @Test(arguments: [
        ("racerender-basic.csv", "racerender-csv"), ("racechrono-v3.csv", "racechrono-csv"), ("track.gpx", "gpx"),
    ])
    func picksTheRightImporter(fixture: String, expected: String) throws {
        let candidate = try #require(try FormatDetector.detect(try Fixtures.url(fixture)))
        #expect(candidate.id == expected)
    }

    @Test func importSessionFillsFileName() throws {
        let session = try FormatDetector.importSession(at: try Fixtures.url("track.gpx"))
        #expect(session.info.sourceFileName == "track.gpx")
    }

    @Test func unknownFileIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "x-\(UUID().uuidString).bin")
        try Data([0, 1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try FormatDetector.detect(url) == nil)
        #expect(throws: ImportError.unrecognisedFormat) { try FormatDetector.importSession(at: url) }
    }
}

@Suite("RaceChrono CSV v2 importer")
struct RaceChronoV2Tests {
    @Test func parsesV2HeaderNames() {
        let lateral = RaceChronoCSVImporter.parseV2Header("Lateral acceleration (G) *calc")
        #expect(lateral.key == "lateral_acc" && lateral.unit == "G" && lateral.source == "calc")
        let time = RaceChronoCSVImporter.parseV2Header("Time (s)")
        #expect(time.key == "timestamp" && time.unit == "s" && time.source.isEmpty)
        let gear = RaceChronoCSVImporter.parseV2Header("Gear *canbus")
        #expect(gear.key == "gear" && gear.unit.isEmpty && gear.source == "canbus")
        let rot = RaceChronoCSVImporter.parseV2Header("X rate of rotation (deg/s) *gyro")
        #expect(rot.key == "x_gyro" && rot.unit == "deg/s")
        #expect(RaceChronoCSVImporter.parseV2Header("Analog 1 *canbus").key == "analog_1")
        #expect(RaceChronoCSVImporter.parseV2Header("Trap name").key == "trap_name")
    }

    @Test func importsTheV2Fixture() throws {
        let url = try Fixtures.url("racechrono-v2.csv")
        let sniff = try FileSniff.sniff(url)
        #expect(RaceChronoCSVImporter.confidence(for: sniff) == .certain)
        let table = try RaceChronoCSVImporter().importFile(at: url)
        #expect(table.info.title == "Test Circuit")
        #expect(table.rowCount == 8)
        #expect(table.times.first == 1_787_528_164.60)
        let speeds = table.columns.filter { $0.name == "speed" }
        #expect(speeds.count == 3)
        #expect(speeds[0].source == nil && speeds[0].suggestedRole == .speed && speeds[0].unit == .metersPerSecond)
        #expect(speeds[1].source == "calc" && speeds[1].suggestedRole == .speed)
        #expect(speeds[2].source == "canbus" && speeds[2].suggestedRole == .obd("speed"))
        #expect(table.column(named: "rpm")?.suggestedRole == .rpm)
        #expect(table.column(named: "rpm")?.values[5] == nil)  // blank CAN cell
        #expect(table.column(named: "brake_pos")?.suggestedRole == .brake)
        #expect(table.column(named: "throttle_pos")?.suggestedRole == .throttle)
        #expect(table.column(named: "accuracy")?.suggestedRole == .accuracy)
        #expect(table.column(named: "lateral_acc")?.suggestedRole == .lateralG)
        #expect(table.column(named: "trap_name")?.values.allSatisfy { $0 == nil } == true)
        #expect(table.column(named: "steering_angle")?.unit == .degrees)
        #expect(table.column(named: "x_gyro")?.unit == .custom("deg/s"))
    }

    @Test func v2SessionHasLapsAndCanonicalChannels() throws {
        let session = try RaceChronoCSVImporter().importSession(at: try Fixtures.url("racechrono-v2.csv"))
        #expect(session.laps.map(\.number) == [1, 2])
        #expect(session.laps[0].start == 1_787_528_165.0)
        #expect(session[.speed]?.count == 8)
        #expect(session[.obd("speed")] != nil)
        #expect(session[.aux("speed (calc)")] != nil)
        #expect(session[.accuracy]?.unit == .meters)
        #expect(session[.gear]?.interpolation == .step)
        #expect(session[.rpm]?.count == 7)
        #expect(session[.heading]?.value(at: 1_787_528_165.3) == 90)
        #expect(session[.aux("trap_name")] == nil)
    }
}

@Suite("TCX importer")
struct TCXImporterTests {
    @Test func importsLapsAndExtensions() throws {
        let url = try Fixtures.url("activity.tcx")
        #expect(TCXImporter.confidence(for: try FileSniff.sniff(url)) == .certain)
        let table = try TCXImporter().importFile(at: url)
        #expect(table.rowCount == 4 && table.times == [0, 1, 2, 3])
        #expect(table.column(named: "Speed")?.suggestedRole == .speed)
        #expect(table.column(named: "Power")?.values[0] == 200)
        #expect(table.column(named: "Heart rate")?.values[3] == nil)
        #expect(table.lapMarkers == [RawLapMarker(number: 0, time: 2)])
        let session = try TCXImporter().importSession(at: url)
        #expect(session.laps.map(\.number) == [0, 1])
        #expect(session.info.title == "Biking")
        #expect(try FormatDetector.detect(url)?.id == "tcx")
    }
}

@Suite("NMEA importer")
struct NMEAImporterTests {
    @Test func parsesSentences() throws {
        let url = try Fixtures.url("track.nmea")
        #expect(NMEAImporter.confidence(for: try FileSniff.sniff(url)) == .certain)
        let table = try NMEAImporter().importFile(at: url)
        #expect(table.rowCount == 4)
        #expect(table.times == [0, 1, 2, 3])
        #expect(abs((table.column(named: "Latitude")?.values[1] ?? 0) - 45.00009) < 1e-6)
        #expect(abs((table.column(named: "Longitude")?.values[0] ?? 0) + 122) < 1e-9)
        #expect(abs((table.column(named: "Speed")?.values[0] ?? 0) - 10) < 0.01)  // 19.44 kn
        #expect(table.column(named: "Course")?.values[2] == 90)
        #expect(table.column(named: "Altitude")?.values[3] == 102)
        #expect(table.column(named: "Satellites")?.values[3] == 9)
        let created = try #require(table.info.createdAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        #expect(calendar.component(.year, from: created) == 2026 && calendar.component(.hour, from: created) == 12)
    }

    @Test func helpers() throws {
        #expect(NMEAImporter.utcSeconds("120001.50") == 43201.5)
        #expect(NMEAImporter.coordinate("4500.0000", hemisphere: "N") == 45)
        #expect(NMEAImporter.coordinate("12230.0000", hemisphere: "W") == -122.5)
        #expect(try FormatDetector.detect(try Fixtures.url("track.nmea"))?.id == "nmea")
    }
}

@Suite("VBO importer")
struct VBOImporterTests {
    @Test func parsesHeaderAndData() throws {
        let url = try Fixtures.url("session.vbo")
        #expect(VBOImporter.confidence(for: try FileSniff.sniff(url)) == .certain)
        let table = try VBOImporter().importFile(at: url)
        #expect(table.rowCount == 5 && table.times == [0, 1, 2, 3, 4])
        #expect(abs((table.column(named: "lat")?.values[0] ?? 0) - 45) < 1e-9)
        #expect(abs((table.column(named: "long")?.values[0] ?? 0) + 122) < 1e-9)
        #expect(table.column(named: "velocity")?.unit == .kilometersPerHour)
        #expect(table.column(named: "lapnumber")?.suggestedRole == .lap)
        let session = try VBOImporter().importSession(at: url)
        #expect(abs((session[.speed]?.values[0] ?? 0) - 20) < 1e-6)
        #expect(session.laps.map(\.number) == [1, 2])
        #expect(session.info.createdAt != nil)
        #expect(try FormatDetector.detect(url)?.id == "vbo")
    }
}

@Suite("Generic CSV importer")
struct GenericCSVImporterTests {
    @Test func harrysProfile() throws {
        let url = try Fixtures.url("harrys.csv")
        let table = try GenericCSVImporter().importFile(at: url)
        #expect(table.info.sourceFormat.contains("Harry"))
        #expect(table.column(named: "Speed (km/h)")?.suggestedRole == .speed)
        #expect(table.column(named: "Speed (km/h)")?.unit == .kilometersPerHour)
        #expect(table.column(named: "Lap")?.suggestedRole == .lap)
        let session = try GenericCSVImporter().importSession(at: url)
        #expect(abs((session[.speed]?.values[0] ?? 0) - 20) < 1e-6)
        #expect(session.laps.map(\.number) == [1, 2])
        #expect(try FormatDetector.detect(url)?.id == "generic-csv")
    }

    @Test func fuzzyNamesAndClockTimes() throws {
        let url = try Fixtures.url("generic.csv")
        let table = try GenericCSVImporter().importFile(at: url)
        #expect(table.times == [0, 0.5, 1])
        #expect(
            table.column(named: "mph")?.suggestedRole == .speed && table.column(named: "mph")?.unit == .milesPerHour)
        #expect(table.column(named: "course")?.suggestedRole == .heading)
        #expect(table.column(named: "lateral g")?.suggestedRole == .lateralG)
        #expect(table.column(named: "long g")?.suggestedRole == .longitudinalG)
        #expect(table.column(named: "gear")?.interpolation == .step)
        #expect(try FormatDetector.detect(url)?.id == "generic-csv")
    }

    @Test func racechronoAndRacerenderStillWinDetection() throws {
        #expect(try FormatDetector.detect(try Fixtures.url("racechrono-v3.csv"))?.id == "racechrono-csv")
        #expect(try FormatDetector.detect(try Fixtures.url("racerender-basic.csv"))?.id == "racerender-csv")
    }
}
