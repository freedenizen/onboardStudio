import Foundation
import TelemetryKit
import Testing

@testable import Importers

/// #73: a VBO file says what its channels are measured in, in two places the importer used to
/// read neither of.
@Suite("VBO declared units")
struct VBOUnitTests {
    func table() throws -> RawTable {
        try VBOImporter().importFile(at: try Fixtures.url("vbox-canbus.vbo"))
    }

    func column(_ table: RawTable, _ name: String) throws -> RawColumn {
        try #require(table.columns.first { $0.name == name }, "no column \(name)")
    }

    // MARK: - [channel units] is right-aligned

    /// The file lists 14 channels and 6 units, and the units belong to the **last** six. Aligning
    /// from the top instead gives every CAN channel its neighbour's unit — bar for a temperature,
    /// rpm for a pressure — which is worse than no unit at all, because it looks right.
    @Test func unitsBelongToTheLastChannels() throws {
        let table = try table()
        #expect(try column(table, "Brake_Pressure").unit == .bar)
        #expect(try column(table, "Coolant_Temperature").unit == .celsius)
        #expect(try column(table, "Engine_Speed").unit == .rpm)
        #expect(try column(table, "Battery_Voltage").unit == .volts)
        #expect(try column(table, "Tsample").unit == .seconds)
    }

    /// `(null)` is how the format writes "no unit". It must not become a unit called `(null)`,
    /// which would belong to no family and so convert to nothing. It means the file declares
    /// nothing, so the importer's own reading of the name stands — a gear is a count.
    @Test func nullMeansTheFileDeclaresNothing() throws {
        let gear = try column(try table(), "Gear")
        #expect(gear.unit == .count)
        #expect(gear.unit != .custom("(null)"), "the marker is not a unit")
    }

    /// The GPS channels at the top get no unit line, and must not be given one.
    @Test func theLeadingChannelsKeepTheirOwnUnits() throws {
        let table = try table()
        #expect(try column(table, "lat").unit == .degrees)
        #expect(try column(table, "height").unit == .meters)
    }

    @Test func alignmentIsComputedFromTheEnd() {
        let header = ["satellites", "time", "latitude", "RPM", "Brake"]
        let units = VBOImporter.declaredUnits(header: header, units: ["rpm", "psi"], columns: 5)
        #expect(units == [nil, nil, nil, .rpm, .psi])
    }

    /// A file with no units section, which is most of them, must import exactly as it did.
    @Test func noUnitsSectionDeclaresNothing() throws {
        #expect(VBOImporter.declaredUnits(header: ["a", "b"], units: [], columns: 2) == [nil, nil])
        let plain = try VBOImporter().importFile(at: try Fixtures.url("session.vbo"))
        #expect(try column(plain, "velocity").unit == .kilometersPerHour, "the VBO default still stands")
    }

    // MARK: - The header name carries the unit

    /// `velocity kmh` and `velocity knots` both collapse to `velocity` in `[column names]`, so the
    /// unit can only come from `[header]`. Reading a knots file as km/h is wrong by 1.852 and
    /// silent — the 2004 Racelogic user-guide example is exactly such a file.
    @Test func aVelocityInKnotsIsNotKilometresPerHour() throws {
        let table = try table()
        #expect(try column(table, "velocity").unit == .knots)
        let session = try VBOImporter().importSession(at: try Fixtures.url("vbox-canbus.vbo"))
        // 15.13 knots is 7.78 m/s. Read as km/h it would have been 4.20.
        #expect(abs(try #require(session[.speed]).values[0] - 7.784) < 0.01)
    }

    @Test func verticalVelocityTakesItsUnitFromItsName() throws {
        #expect(try column(try table(), "vert-vel").unit == .metersPerSecond)
    }

    /// A name whose last word merely looks like a word, not a unit, keeps its name intact.
    @Test func aNameEndingInAWordIsNotAUnit() {
        #expect(VBOImporter.unitSuffix(of: "Air Fuel Ratio") == nil)
        #expect(VBOImporter.unitSuffix(of: "solution type") == nil)
        #expect(VBOImporter.unitSuffix(of: "velocity") == nil, "one word is a name, not a unit")
        #expect(VBOImporter.unitSuffix(of: "velocity kmh") == .kilometersPerHour)
        #expect(VBOImporter.unitSuffix(of: "yaw rate deg/s") == .degreesPerSecond)
    }
}

/// The same importer against files a real VBOX wrote. They are not committed — provenance is
/// third-party and one is explicitly copyrighted — so these skip unless `ONBOARD_SAMPLES_DIR`
/// points at a folder with a `vbo/` directory in it. See that folder's README.
@Suite("VBO against real logger files")
struct VBOSampleTests {
    func sample(_ name: String) throws -> RawTable? {
        guard let samples = ProcessInfo.processInfo.environment["ONBOARD_SAMPLES_DIR"] else { return nil }
        let url = URL(fileURLWithPath: (samples as NSString).expandingTildeInPath)
            .appending(path: "vbo").appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try VBOImporter().importFile(at: url)
    }

    func column(_ table: RawTable, _ name: String) throws -> RawColumn {
        try #require(table.columns.first { $0.name == name }, "no column \(name)")
    }

    /// The VBOX Pro Lite user-guide example, which logs `velocity knots` and has an empty
    /// `[channel units]`. Before the header name was read it imported 1.852× too slow.
    @Test func theUserGuideExampleIsInKnots() throws {
        guard let table = try sample("racelogic-pro-lite-2004.vbo") else { return }
        #expect(try column(table, "velocity").unit == .knots)
    }

    /// The file that settled the alignment question: 35 channels, 25 unit lines.
    @Test func aThirtyFiveChannelLogGetsAllTwentyFiveUnits() throws {
        guard let table = try sample("vbvdhd2-VBOX0133.vbo") else { return }
        #expect(try column(table, "Brake_Pressure").unit == .bar)
        #expect(try column(table, "Coolant_Temperature").unit == .celsius)
        #expect(try column(table, "Engine_Speed").unit == .rpm)
        #expect(try column(table, "Oil_Temp_(Calc)").unit == .fahrenheit)
        #expect(try column(table, "Steering_Angle").unit == .degrees)
        #expect(try column(table, "Indicated_Vehicle_Speed").unit == .kilometersPerHour)
        #expect(try column(table, "Gear").unit != .custom("(null)"), "`(null)` is not a unit")
        #expect(try column(table, "lat").unit == .degrees, "and the GPS channels are untouched")
    }

    /// A Video VBOX whose `Brake` channel is a pressure in psi, not the percentage the importer's
    /// own name-based guess assumes. What the file says beats what the name suggests.
    @Test func aDeclaredUnitBeatsTheNameBasedGuess() throws {
        guard let table = try sample("videovbox-VBOX0001.vbo") else { return }
        #expect(try column(table, "Brake").unit == .psi)
        #expect(try column(table, "TPS").unit == .percent)
        #expect(try column(table, "RPM").unit == .rpm)
    }

    /// The two VBVDHD2 logs carry a real `[laptiming]` line, and it is what settled the
    /// coordinate order: read the other way round this gate lands at latitude 122.
    @Test func aRealLogsStartLineIsWhereTheSessionIs() throws {
        guard let table = try sample("vbvdhd2-VBOX0133.vbo") else { return }
        let start = try #require(table.lapGeometry.start)
        #expect(abs(start.centreLatitude - 39.5385) < 0.001, "the session runs at 39.537 N")
        #expect(abs(start.centreLongitude - -122.3312) < 0.001, "and 122.332 W")
        #expect(start.label == "Start / Finish")
        #expect(table.lapGeometry.splits.isEmpty, "this logger recorded no sector gates")
    }

    /// Every sample file must at least import, whatever its vintage and spacing.
    @Test(arguments: [
        "racelogic-pro-lite-2004.vbo", "vbvdhd2-VBOX0133.vbo", "vbvdhd2-VBOX0134.vbo",
        "videovbox-VBOX0001.vbo", "vbo-reader-new-format.vbo", "daq-tools-sample.vbo",
    ])
    func everySampleImports(name: String) throws {
        guard let table = try sample(name) else { return }
        #expect(!table.columns.isEmpty, "\(name) produced no columns")
        #expect(!table.times.isEmpty, "\(name) produced no samples")
    }
}

/// #71: `[laptiming]` is the only place in any surveyed format where start/finish and sector
/// geometry is stored as geometry rather than as lap times.
@Suite("VBO lap timing gates")
struct VBOLapTimingTests {
    func geometry() throws -> LapGeometry {
        try VBOImporter().importFile(at: try Fixtures.url("vbox-canbus.vbo")).lapGeometry
    }

    /// **Longitude first, then latitude** — the reverse of `[data]`. Settled against two real
    /// VBVDHD2 logs: the session sits at 39.537 N, 122.332 W, so 7339.87 minutes (122.331°) can
    /// only be the longitude. Read the other way round the gate lands at latitude 122, which does
    /// not exist.
    @Test func coordinatesAreLongitudeThenLatitude() throws {
        let start = try #require(try geometry().start)
        #expect(abs(start.startLatitude - 39.538_480) < 1e-5)
        #expect(abs(start.startLongitude - -122.331_177) < 1e-5, "minutes, west positive, negated")
        #expect(abs(start.endLatitude - 39.538_571) < 1e-5)
        #expect(start.label == "Start / Finish")
    }

    /// The gate's own width beats any default: a logger draws the line as wide as the track is.
    @Test func theGateKnowsItsOwnWidth() throws {
        let start = try #require(try geometry().start)
        // The endpoints are ~10 m apart, so the line reaches about 5 m either side of centre.
        #expect(start.halfWidthMeters > 3 && start.halfWidthMeters < 8, "\(start.halfWidthMeters)")
        #expect(abs(start.centreLatitude - 39.538_525) < 1e-5)
    }

    @Test func splitsAreSectorsAndKeepTheirOrder() throws {
        let geometry = try geometry()
        #expect(geometry.gates.count == 4)
        #expect(geometry.splits.count == 2, "the start/finish is not a sector boundary")
        #expect(geometry.splits.first?.label == "Split 1")
        #expect(geometry.splits.last?.label.isEmpty == true, "a gate the logger named nothing")
        #expect(geometry.gates.last?.kind == .finish)
    }

    @Test func aFileWithNoSectionCarriesNoGates() throws {
        let plain = try VBOImporter().importFile(at: try Fixtures.url("session.vbo"))
        #expect(plain.lapGeometry.isEmpty)
    }

    /// Garbage in that section must be skipped, not guessed at.
    @Test func unreadableLinesAreIgnored() {
        #expect(VBOImporter.gate("Start +1 +2 +3 ¬ short") == nil, "too few numbers")
        #expect(VBOImporter.gate("Middle +1 +2 +3 +4 ¬ x") == nil, "not a kind this format has")
        #expect(VBOImporter.gate("") == nil)
        #expect(VBOImporter.gate("Start a b c d ¬ x") == nil, "not numbers")
        #expect(VBOImporter.gate("Start +7339.87 +2372.30 +7339.88 +2372.31") != nil, "no label is fine")
    }
}
