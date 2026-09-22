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
