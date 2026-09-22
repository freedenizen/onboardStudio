import TelemetryKit
import Testing

@testable import Importers

/// #149: a data file that imports badly has to explain itself. Modelled on a real RaceChrono CAN
/// session — every column becomes a channel, and the trouble is entirely in what they became.
@Suite("Import report")
struct ImportReportTests {
    func report() throws -> ImportReport {
        try RaceChronoCSVImporter().importSession(at: try Fixtures.url("racechrono-v3-noisy.csv")).importReport
    }

    func column(_ report: ImportReport, _ name: String, source: String? = nil) throws -> ImportReport.Column {
        try #require(
            report.columns.first { $0.name == name && (source == nil || $0.source == source) },
            "no column \(name)\(source.map { " from \($0)" } ?? "")")
    }

    @Test func everyColumnOfTheFileIsAccountedFor() throws {
        let report = try report()
        // 32 columns in the file; `timestamp` becomes the time axis rather than a channel.
        #expect(report.columns.count == 31, "one line per column, including the repeated names")
        #expect(report.columns.map(\.id) == Array(0..<31), "in file order")
        #expect(report.skipped.isEmpty, "this file has nothing the importer rejects outright")
    }

    /// The question a user actually asks when three columns are called `speed`: which one won?
    @Test func aRenamedColumnNamesTheOneThatKeptTheRole() throws {
        let report = try report()
        #expect(try column(report, "speed", source: "100: gps").role == .speed)
        #expect(try column(report, "speed", source: "100: gps").notes.isEmpty)

        // The calculated speed asked for the same role and lost it, so it says who has it.
        let calc = try column(report, "speed", source: "calc")
        #expect(calc.role == .aux("speed (calc)"))
        #expect(calc.notes.contains(.roleTaken(by: "speed", role: .speed)))
        #expect(calc.needsAttention)

        // The CAN speed never competed: the importer files a `200: canbus` column under its own
        // source, so it is a CAN channel that happens to share a name, not a demoted speed.
        let canbus = try column(report, "speed", source: "200: canbus")
        #expect(canbus.role == .canbus("speed"))
        #expect(canbus.notes.isEmpty)
    }

    /// The analog inputs: no unit, and no name the importer can make anything of.
    @Test func aColumnNothingIsKnownAboutSaysSo() throws {
        let report = try report()
        let analog = try column(report, "analog_1")
        #expect(analog.role == .canbus("analog_1"), "it is still imported, under its own name")
        #expect(analog.notes.contains(.noUnit))
        #expect(analog.needsAttention)

        // A gear is measured in nothing, and saying so about every such column would bury the
        // warnings that matter.
        #expect(try !column(report, "gear").notes.contains(.noUnit))
        #expect(try !column(report, "lap_number").notes.contains(.noUnit))
    }

    /// A sensor reading the same number all session is usually not connected. `analog_3` is the
    /// spare input; `fix_type` and `fragment_id` are constants the file always writes.
    @Test func aChannelThatNeverChangesIsFlagged() throws {
        let report = try report()
        #expect(try column(report, "analog_3").notes.contains(.constant(0)))
        #expect(try column(report, "fix_type").notes.contains(.constant(3)))
        #expect(try column(report, "coolant_temp").notes.isEmpty, "a real reading is not flagged")
    }

    /// A unit the app does not know is worth saying, because such a channel silently belongs to
    /// no family and so converts to nothing.
    @Test func anUnknownUnitIsFlagged() throws {
        let report = try report()
        #expect(try column(report, "satellites").notes.contains(.unknownUnit("sats")))
        #expect(try column(report, "coolant_temp").unit == .celsius, "but `.C` is known now")
        #expect(try column(report, "z_rate_of_rotation").unit == .degreesPerSecond)
    }

    @Test func theSummaryCountsWhatMatters() throws {
        let report = try report()
        #expect(report.read.count == report.columns.count)
        #expect(!report.needingAttention.isEmpty)
        #expect(report.summary.contains("31 columns"))
        #expect(report.summary.contains("worth a look"))
    }

    /// A clean file says nothing, which is the point: the panel is quiet unless it has something.
    @Test func aCleanFileRaisesNothing() throws {
        let report = try RaceChronoCSVImporter()
            .importSession(at: try Fixtures.url("racechrono-v3.csv")).importReport
        let noisy = report.needingAttention.filter { $0.name == "speed" }
        #expect(!noisy.isEmpty, "that fixture does repeat `speed`")
        #expect(try column(report, "throttle_pos").notes.isEmpty)
        #expect(try column(report, "rpm").notes.isEmpty)
    }
}
