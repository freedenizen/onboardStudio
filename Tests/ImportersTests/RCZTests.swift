import Foundation
import TelemetryKit
import Testing

@testable import Importers

/// #68: a RaceChrono `.rcz` archive imports on its own, rather than the user being told to export
/// a CSV as well.
@Suite("RaceChrono archive")
struct RCZTests {
    func table() throws -> RawTable {
        try RCZImporter().importFile(at: try Fixtures.url("session.rcz"))
    }

    func session() throws -> TelemetrySession {
        try RCZImporter().importSession(at: try Fixtures.url("session.rcz"))
    }

    func sniff(_ name: String, _ head: String) -> FileSniff {
        FileSniff(url: URL(fileURLWithPath: "/tmp/\(name)"), head: head)
    }

    @Test func theArchiveIsRecognisedButAPlainZipIsNot() {
        #expect(RCZImporter.confidence(for: sniff("s.rcz", "PK\u{03}\u{04}")) == .certain)
        #expect(RCZImporter.confidence(for: sniff("s.zip", "PK\u{03}\u{04}")) == .no, "an .rcz by extension")
        #expect(RCZImporter.confidence(for: sniff("s.rcz", "timestamp,")) == .no, "and a zip by content")
    }

    /// The scales are exact, not fitted: each was read off a session exported both ways.
    @Test func gpsChannelsDecodeToTheirRealUnits() throws {
        let session = try session()
        #expect(try #require(session[.speed]).unit == .metersPerSecond)
        #expect(abs(try #require(session[.speed]).values[0] - 28) < 1e-6, "mm/s")
        #expect(abs(try #require(session[.altitude]).values[0] - 12) < 1e-6, "mm")
        #expect(abs(try #require(session[.heading]).values[0] - 90) < 1e-6, "millidegrees")
        #expect(abs(try #require(session[.accuracy]).values[0] - 0.4) < 1e-6, "mm")
        #expect(try #require(session[.aux("satellites")]).values[0] == 13, "unscaled")
    }

    /// Position is an int32 pair over 6,000,000 — minutes × 10⁵ — not the 1e7 most formats use.
    /// Getting that wrong puts the session in the wrong hemisphere rather than slightly off.
    @Test func positionsUseTheMinutesScale() throws {
        let session = try session()
        #expect(abs(try #require(session[.latitude]).values[0] - 38.161_025) < 1e-6)
        #expect(abs(try #require(session[.longitude]).values[0] - -122.454) < 1e-6)
    }

    /// Distance is int64 millimetres, and reading it as int32 silently truncates it — which then
    /// makes every lap delta nonsense, because those compare at the same distance into a lap.
    @Test func distanceIsReadAsSixtyFourBits() throws {
        let distance = try #require(try session()[.distance])
        #expect(abs(try #require(distance.maxValue) - 43.68) < 1e-6)
    }

    @Test func theImuDevicesKeepTheirOwnClock() throws {
        let session = try session()
        let accelerometer = try #require(session[.aux("x_acc")])
        #expect(accelerometer.unit == .gForce)
        #expect(accelerometer.count == 41, "one more record than the GPS device has")
        #expect(try #require(session[.aux("z_rate_of_rotation")]).unit == .degreesPerSecond)
    }

    /// A CAN channel is logged at its own rate and its values are float64 in a separate member.
    /// The archive carries no name for it, so it keeps the logger's id and the user says what it
    /// is in the attribute table (#111).
    @Test func canChannelsKeepTheirIdsAndTheirOwnRates() throws {
        let session = try session()
        let brake = try #require(session[.canbus("66569")])
        #expect(brake.count == 16)
        #expect(brake.maxValue == 11200)
        let rpm = try #require(session[.canbus("10024")])
        #expect(rpm.count == 32, "a different rate from the brake channel and from the GPS")
        #expect(rpm.values[0] == 4100)
    }

    /// Each CAN channel also carries the distance at every sample. It only repeats the GPS
    /// device's, and keeping it gave every CAN channel a twin under its own name.
    @Test func aCanChannelHasNoDistanceTwin() throws {
        let names = try table().columns.filter { $0.name.hasPrefix("canbus_") }.map(\.name)
        #expect(names.count == Set(names).count, "a CAN channel appears once: \(names)")
        #expect(names.count == 2)
    }

    @Test func theTrackNameAndLapsComeFromTheArchive() throws {
        let table = try table()
        #expect(table.info.trackName == "Synthetic")
        #expect(table.lapMarkers.map(\.number) == [1, 2])
        #expect(try session().laps.count >= 1)
    }

    /// Every device samples on its own clock, so the table's axis is the union of all of them and
    /// a channel keeps the times it was actually recorded at rather than being resampled.
    @Test func theAxisIsTheUnionOfEveryDeviceClock() throws {
        let table = try table()
        #expect(table.times.count >= 41)
        #expect(table.times == table.times.sorted())
        #expect(Set(table.times).count == table.times.count, "no duplicate rows")
    }
}

/// The real archive, against the CSV export of the very same session. Neither file is committed,
/// so this skips unless `ONBOARD_SAMPLES_DIR` is set.
@Suite("RaceChrono archive against the reference session")
struct RCZReferenceTests {
    func url(_ name: String) -> URL? {
        guard let samples = ProcessInfo.processInfo.environment["ONBOARD_SAMPLES_DIR"] else { return nil }
        let url = URL(fileURLWithPath: (samples as NSString).expandingTildeInPath).appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The archive and the CSV are two renderings of one session, so the channels they share must
    /// agree. This is the check the whole decode was derived from, kept as a test.
    @Test func theArchiveAgreesWithTheCsvExport() throws {
        guard let archive = url("session_20260823_163604_sonoma.rcz"),
            let csv = url("session_20260823_163604_sonoma_v3.csv")
        else { return }
        let fromArchive = try RCZImporter().importSession(at: archive)
        let fromCSV = try RaceChronoCSVImporter().importSession(at: csv)

        for role in [ChannelRole.speed, .altitude, .distance, .accuracy] {
            let a = try #require(fromArchive[role], "\(role.identifier) missing from the archive")
            let c = try #require(fromCSV[role], "\(role.identifier) missing from the CSV")
            #expect(
                abs(try #require(a.maxValue) - (try #require(c.maxValue))) < 0.01,
                "\(role.identifier) disagrees: \(a.maxValue ?? 0) vs \(c.maxValue ?? 0)")
        }
        #expect(fromArchive.info.trackName == "Sonoma")
    }

    /// The CAN channels are the same data under the logger's ids instead of its names — brake
    /// pressure in kPa peaking at the same number in both.
    @Test func theCanChannelsMatchTheirNamedCounterparts() throws {
        guard let archive = url("session_20260823_163604_sonoma.rcz"),
            let csv = url("session_20260823_163604_sonoma_v3.csv")
        else { return }
        let fromArchive = try RCZImporter().importSession(at: archive)
        let fromCSV = try RaceChronoCSVImporter().importSession(at: csv)
        let brakeByID = try #require(fromArchive[.canbus("66569")])
        let brakeByName = try #require(fromCSV[.canbus("brake_pressure_front")])
        #expect(abs(try #require(brakeByID.maxValue) - (try #require(brakeByName.maxValue))) < 0.01)
    }

    /// The archive keeps the logger's own lap list, which is what it is worth having for.
    @Test func theLapsComeFromTheLoggerRatherThanFromAGuess() throws {
        guard let archive = url("session_20260823_163604_sonoma.rcz") else { return }
        let session = try RCZImporter().importSession(at: archive)
        #expect(session.laps.count == 9)
        let best = session.laps.filter(\.isComplete).compactMap(\.duration).min()
        #expect(abs(try #require(best) - 116.883) < 0.01, "session.json says bestLaptime 116883 ms")
    }
}
