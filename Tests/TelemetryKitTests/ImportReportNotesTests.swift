import Testing

@testable import TelemetryKit

/// The notes the import report attaches to one column, at the level where the decisions are made.
/// `ImportReportTests` in ImportersTests covers a whole file; these are the awkward singles.
@Suite("Import report notes")
struct ImportReportNotesTests {
    func table(_ columns: [RawColumn], times: [Double] = [0, 1]) -> RawTable {
        RawTable(info: SessionInfo(sourceFormat: "test"), times: times, columns: columns)
    }

    func column(_ report: ImportReport, _ name: String) throws -> ImportReport.Column {
        try #require(report.columns.first { $0.name == name }, "no column \(name)")
    }

    /// A guess that loses its role must name the column that took it — and the user's mapping can
    /// point at a column *later* in the file, which is when the winner is not yet known by file
    /// order. Naming itself is the failure this guards.
    @Test func aDemotedColumnNeverNamesItself() throws {
        let raw = table([
            RawColumn(name: "speed", unit: .metersPerSecond, suggestedRole: .speed, values: [10, 12]),
            RawColumn(name: "wheel_speed", unit: .metersPerSecond, values: [11, 13]),
        ])
        let session = SessionBuilder.build(raw, options: .init(sourceColumns: [.speed: "wheel_speed"]))
        let demoted = try column(session.importReport, "speed")
        #expect(demoted.notes.contains(.roleTaken(by: "wheel_speed", role: .speed)))
        #expect(!demoted.notes.contains(.roleTaken(by: "speed", role: .speed)), "it must not name itself")
    }

    /// The same, with the winner earlier in the file, which is the ordinary duplicate case.
    @Test func aDuplicateNamesTheColumnThatCameFirst() throws {
        let raw = table([
            RawColumn(name: "GPS Speed", unit: .metersPerSecond, suggestedRole: .speed, values: [10, 12]),
            RawColumn(name: "CAN Speed", unit: .metersPerSecond, suggestedRole: .speed, values: [11, 13]),
        ])
        let report = SessionBuilder.build(raw).importReport
        #expect(try column(report, "CAN Speed").notes.contains(.roleTaken(by: "GPS Speed", role: .speed)))
    }

    /// `makeChannel` refuses a column whose samples are all NaN or infinite, and such a column was
    /// being reported as though nothing had recognised it — discarding the real mapping and the
    /// user's own instruction along with it.
    @Test func aRecognisedColumnWithNothingUsableSaysSo() throws {
        let raw = table([
            RawColumn(name: "Speed", unit: .metersPerSecond, suggestedRole: .speed, values: [.nan, .infinity])
        ])
        let entry = try column(SessionBuilder.build(raw).importReport, "Speed")
        #expect(entry.notes.contains(.empty))
        #expect(!entry.notes.contains(.noMeaning), "something did recognise it")
        #expect(entry.role == nil, "but no channel came of it")
    }

    @Test func aColumnTheUserNamedKeepsThatNoteEvenWithNothingUsable() throws {
        let raw = table([RawColumn(name: "Brake press", values: [.nan, .nan])])
        let session = SessionBuilder.build(raw, options: .init(sourceColumns: [.brake: "Brake press"]))
        let entry = try column(session.importReport, "Brake press")
        #expect(entry.notes.contains(.mapped))
        #expect(entry.notes.contains(.empty))
        #expect(entry.role == nil)
    }

    /// Nothing claimed it, so that is what it says — and only that.
    @Test func anUnclaimedColumnSaysNothingRecognisedIt() throws {
        let raw = table([RawColumn(name: "Ignored", values: [1, 2])])
        let entry = try column(SessionBuilder.build(raw).importReport, "Ignored")
        #expect(entry.notes.contains(.noMeaning))
        #expect(!entry.notes.contains(.empty), "it has values; nothing knew what they were")
        #expect(entry.role == nil)
    }

    // MARK: - When a missing unit is worth raising

    /// A column that was never imported already reads "not imported"; telling the user to set a
    /// unit for it under Attributes is contradictory and unactionable.
    @Test func aColumnThatWasNotImportedIsNotToldToSetAUnit() throws {
        let raw = table([RawColumn(name: "Ignored", values: [1, 2])])
        #expect(try !column(SessionBuilder.build(raw).importReport, "Ignored").notes.contains(.noUnit))
    }

    /// The point of the note: something measured, with no unit to measure it in. A speed is that
    /// whether or not the app recognised the column, and it was being suppressed.
    @Test func aMeasuredChannelWithNoUnitIsRaised() throws {
        let raw = table([
            RawColumn(name: "Speed", suggestedRole: .speed, values: [10, 12]),
            RawColumn(name: "Coolant", suggestedRole: .canbus("Coolant"), values: [80, 90]),
        ])
        let report = SessionBuilder.build(raw).importReport
        #expect(try column(report, "Speed").notes.contains(.noUnit), "a speed is measured in something")
        #expect(try column(report, "Coolant").notes.contains(.noUnit))
    }

    /// A gear and a lap number are a count and an identifier. Saying they have no unit would be
    /// true and useless, and would bury the warnings that matter.
    @Test func aCountOrAnIdentifierIsNotRaised() throws {
        let raw = table([
            RawColumn(name: "Gear", suggestedRole: .gear, values: [3, 4]),
            RawColumn(name: "Lap", suggestedRole: .lap, values: [1, 1]),
        ])
        let report = SessionBuilder.build(raw).importReport
        #expect(try !column(report, "Gear").notes.contains(.noUnit))
        #expect(try !column(report, "Lap").notes.contains(.noUnit))
    }

    @Test func aChannelWithAUnitRaisesNothing() throws {
        let raw = table([RawColumn(name: "Speed", unit: .metersPerSecond, suggestedRole: .speed, values: [10, 12])])
        #expect(try column(SessionBuilder.build(raw).importReport, "Speed").notes.isEmpty)
    }
}
