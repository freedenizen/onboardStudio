import Foundation
import TelemetryKit
import Testing

@testable import Importers

/// Channels a file has no names for, and what is said of them (#657).
@Suite("Unnamed channels (#657)")
struct UnnamedChannelsTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures")

    @Test func aChannelKnownByANumberAloneIsUnnamed() {
        #expect(UnnamedChannels.isUnnamed(.canbus("66569")))
        #expect(!UnnamedChannels.isUnnamed(.canbus("coolant_temp")), "the CSV export names it")
        #expect(!UnnamedChannels.isUnnamed(.canbus("")))
        #expect(!UnnamedChannels.isUnnamed(.aux("12")), "only a CAN channel comes without a name")
        #expect(!UnnamedChannels.isUnnamed(.rpm))
    }

    @Test func anArchiveHasThemAndItsCSVExportDoesNot() throws {
        let archive = try RCZImporter().importSession(
            at: Self.fixtures.appending(path: "session.rcz"), options: SessionBuilder.Options())
        #expect(UnnamedChannels.count(in: archive) == 2)
        #expect(UnnamedChannels.hasOnlyRawAxes(archive), "x, y and z, and neither lateral nor longitudinal G")
        let notice = try #require(UnnamedChannels.notice(for: archive, namesInCSV: true))
        #expect(notice.hasPrefix("2 channels have no name in this file, only the logger's number."))
        #expect(notice.contains("RaceChrono's CSV export of the same session carries the names."))
        #expect(notice.contains("Lateral G and Longitudinal G"))

        let csv = try FormatDetector.importSession(at: Self.fixtures.appending(path: "racechrono-v3-canbus.csv"))
        #expect(UnnamedChannels.count(in: csv) == 0)
    }

    @Test func aFileWithNamesSaysNothing() throws {
        let csv = try FormatDetector.importSession(at: Self.fixtures.appending(path: "racechrono-v3.csv"))
        #expect(UnnamedChannels.notice(for: csv, namesInCSV: false) == nil)
        #expect(UnnamedChannels.notice(unnamed: 0, rawAxes: false, namesInCSV: true) == nil)
    }

    @Test func theWordsCountAndSayOnlyWhatApplies() throws {
        let one = try #require(UnnamedChannels.notice(unnamed: 1, rawAxes: false, namesInCSV: false))
        #expect(one.hasPrefix("1 channel has no name in this file"))
        #expect(!one.contains("RaceChrono") && !one.contains("accelerometer"))
        let axes = try #require(UnnamedChannels.notice(unnamed: 0, rawAxes: true, namesInCSV: true))
        #expect(axes.hasPrefix("Its accelerometer is in the logger's own axes"))
        #expect(!axes.contains("RaceChrono"), "the CSV's names are about the unnamed channels")
    }
}
