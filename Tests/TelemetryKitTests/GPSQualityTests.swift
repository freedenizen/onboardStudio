import Foundation
import Testing

@testable import TelemetryKit

/// #555: what a session's own positions say about how far they can be trusted.
@Suite("GPS quality (#555)")
struct GPSQualityTests {
    /// A car lapping a 100 m circle at a steady speed, a position every `1 / rate` seconds.
    struct Drive {
        var rate = 25.0
        var seconds = 60.0
        var speed = 25.0
        /// Rows faster than the GPS, its position filled in between fixes, as RaceChrono writes.
        var rowRate: Double?
        /// No position in here.
        var missing: Range<Double>?
        /// One position 20 m east of where the car is.
        var jumpAt: Double?
        /// The largest error of a position, varying fix to fix (m).
        var noise = 0.0
        var extra: [Extra] = []

        func table() -> RawTable {
            let step = 1 / (rowRate ?? rate)
            let count = Int(seconds / step)
            var random = UInt64(555)
            var times: [Double] = []
            var latitudes: [Double?] = []
            var longitudes: [Double?] = []
            for index in 0..<count {
                let time = Double(index) * step
                if let missing, missing.contains(time) { continue }
                let angle = speed * time / 100
                var north = 100 * sin(angle)
                var east = 100 * (1 - cos(angle))
                if let jumpAt, abs(time - jumpAt) < step / 2 { east += 20 }
                if noise > 0 {
                    random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    north += noise * (Double(random >> 33) / Double(1 << 31) - 1)
                    random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    east += noise * (Double(random >> 33) / Double(1 << 31) - 1)
                }
                times.append(time)
                latitudes.append(38 + north / 110_540)
                longitudes.append(-122 + east / (111_320 * cos(38 * Double.pi / 180)))
            }
            let columns =
                [
                    RawColumn(name: "lat", unit: .degrees, suggestedRole: .latitude, values: latitudes),
                    RawColumn(name: "lon", unit: .degrees, suggestedRole: .longitude, values: longitudes),
                ]
                + extra.map {
                    RawColumn(
                        name: $0.name, unit: $0.unit, source: $0.source, suggestedRole: $0.role,
                        values: [Double?](repeating: $0.value, count: times.count))
                }
            return RawTable(info: SessionInfo(sourceFormat: "test"), times: times, columns: columns)
        }

        func quality(_ options: SessionBuilder.Options = .init()) throws -> GPSQuality {
            try #require(SessionBuilder.build(table(), options: options).gpsQuality)
        }
    }

    /// A column beside the positions, the same all session.
    struct Extra {
        var name: String
        var unit: TelemetryUnit
        var source: String?
        var role: ChannelRole
        var value: Double
    }

    // MARK: - Rate

    @Test func aFastLoggerIsGoodToTheMetre() throws {
        let quality = try Drive().quality()
        #expect(abs(quality.rateHertz - 25) < 0.1)
        #expect(quality.dropouts.isEmpty && quality.jumps.isEmpty)
        #expect(quality.rating == .good)
        #expect(quality.distanceStep() == 1)
    }

    @Test func onceASecondIsPoorAndRoundsDistancesCoarsely() throws {
        let quality = try Drive(rate: 1, seconds: 120).quality()
        #expect(abs(quality.rateHertz - 1) < 0.01)
        #expect(quality.rating == .poor)
        #expect(quality.findings.first?.issue == .rate(hertz: 1, wanted: 10))
        // 25 m/s for a second, half of it either way.
        #expect(quality.distanceStep() == 15)
        #expect(quality.distanceStep(in: .feet) == 50)
    }

    @Test func fiveASecondIsFair() throws {
        #expect(try Drive(rate: 5).quality().rating == .fair)
    }

    @Test func aRateJustUnderTheThresholdIsTheOneShown() throws {
        // A camera's 9.99 Hz reads "10 positions a second", so it is not "only 10".
        let quality = GPSQuality(rateHertz: 9.99, precisionMeters: 1)
        #expect(GPSQuality.findings(of: quality, options: .init()).isEmpty)
    }

    @Test func positionsFilledInBetweenFixesAreReadAtTheGPSsOwnRate() throws {
        let logged = Extra(
            name: "device_update_rate", unit: .custom("Hz"), source: "100: gps",
            role: .aux("device_update_rate"), value: 25)
        let drive = Drive(rate: 25, rowRate: 100, extra: [logged])
        let session = SessionBuilder.build(drive.table())
        let quality = try #require(session.gpsQuality)
        #expect(abs(quality.rateHertz - 25) < 0.01, "not the rows' 100")
        #expect(session[.gpsRate]?.value(at: 30) == 25)
    }

    @Test func aRateColumnFromAnotherSensorIsNotTheGPSs() throws {
        let other = Extra(
            name: "device_update_rate", unit: .custom("Hz"), source: "101: acc",
            role: .aux("device_update_rate"), value: 400)
        let quality = try Drive(extra: [other]).quality()
        #expect(abs(quality.rateHertz - 25) < 0.1)
    }

    @Test func resamplingDoesNotChangeTheRate() throws {
        var options = SessionBuilder.Options()
        options.resampleHertz = 50
        #expect(abs(try Drive(rate: 10).quality(options).rateHertz - 10) < 0.1)
    }

    // MARK: - Dropouts and jumps

    @Test func aShortDropoutIsFairAndKnowsWhereItWas() throws {
        let quality = try Drive(rate: 10, missing: 20..<22).quality()
        #expect(quality.dropouts.count == 1)
        #expect(abs((quality.dropouts.first?.seconds ?? 0) - 2.1) < 0.05)
        #expect(quality.rating == .fair)
        #expect(quality.hasDropout(between: 21, and: 23))
        #expect(!quality.hasDropout(between: 25, and: 30))
    }

    @Test func aDropoutACornerCanPassInIsPoor() throws {
        #expect(try Drive(rate: 10, missing: 20..<25).quality().rating == .poor)
    }

    @Test func aStrayPositionIsOneJump() throws {
        let quality = try Drive(rate: 10, jumpAt: 30).quality()
        #expect(quality.jumps.count == 1)
        #expect(abs((quality.jumps.first ?? 0) - 30) < 0.2)
        #expect(quality.rating == .fair)
    }

    @Test func ordinaryNoiseIsNotAJump() throws {
        let quality = try Drive(rate: 25, seconds: 300, noise: 0.3).quality()
        #expect(quality.jumps.isEmpty)
    }

    @Test func theGPSRateReadsZeroThroughADropout() throws {
        let session = SessionBuilder.build(Drive(rate: 10, missing: 20..<25).table())
        let rate = try #require(session[.gpsRate])
        #expect(rate.value(at: 15) == 10)
        #expect(rate.value(at: 23) == 0)
    }

    @Test func aTimeAnAgeAwayAsksForNoMoreReadingsThanPositions() throws {
        // A corrupt file: one position a third of a year after the rest.
        let latitude = Channel(
            role: .latitude, name: "lat", unit: .degrees, times: [0, 0.1, 0.2, 0.3, 1e7],
            values: [38, 38.00001, 38.00002, 38.00003, 38.00004])
        let longitude = Channel(
            role: .longitude, name: "lon", unit: .degrees, times: latitude.times,
            values: [-122, -122, -122, -122, -122])
        let rate = try #require(GPSQuality.rateChannel(latitude: latitude, longitude: longitude))
        #expect(rate.count <= 4 * latitude.count)
    }

    // MARK: - What the logger says about itself

    @Test func theLoggersOwnAccuracySatellitesAndHDOPCount() throws {
        let quality = try Drive(extra: [
            .init(name: "accuracy", unit: .meters, source: "100: gps", role: .accuracy, value: 6),
            .init(name: "satellites", unit: .count, role: .aux("satellites"), value: 4),
            .init(name: "HDOP", unit: .custom("DOP"), role: .aux("HDOP"), value: 2),
        ]).quality()
        #expect(quality.accuracyMeters == 6)
        #expect(quality.satellites == 4)
        #expect(quality.hdop == 2)
        #expect(quality.rating == .poor)
        let kinds = quality.findings.map(\.issue)
        #expect(kinds.contains(.accuracy(meters: 6)) && kinds.contains(.satellites(4)) && kinds.contains(.hdop(2)))
        #expect(quality.findings.first?.rating == .poor, "worst first")
        // Six metres either way is what a distance can be off by, however often it arrives.
        #expect(quality.distanceStep() == 10)
    }

    // MARK: - Laps

    @Test func aLapTwiceTheUsualLengthHadItsLineMissed() {
        var session = SessionBuilder.build(Drive(seconds: 400).table())
        session.laps = [
            Lap(number: 1, start: 0, end: 60, isComplete: true),
            Lap(number: 2, start: 60, end: 120, isComplete: true),
            Lap(number: 3, start: 120, end: 240, isComplete: true),
            Lap(number: 4, start: 240, end: 300, isComplete: true),
        ]
        #expect(GPSQuality.longLaps(in: session, factor: 1.6) == [3])
    }

    @Test func twoLapsAreTooFewToSayWhatIsUsual() {
        var session = SessionBuilder.build(Drive().table())
        session.laps = [
            Lap(number: 1, start: 0, end: 20, isComplete: true), Lap(number: 2, start: 20, end: 60, isComplete: true),
        ]
        #expect(GPSQuality.longLaps(in: session, factor: 1.6).isEmpty)
    }

    // MARK: - In words

    @Test func whatADriverReads() throws {
        let quality = try Drive(rate: 1, seconds: 120).quality()
        #expect(quality.measurements(units: .metric) == "1 position a second · distances to about 15 m")
        #expect(quality.messages(units: .metric) == ["Only 1 position a second; corner-level advice needs 10 or more."])
        let long = GPSQuality(
            rateHertz: 25, dropouts: [.init(start: 3, end: 5.5)], longLaps: [4, 7], precisionMeters: 1,
            findings: [
                .init(.dropouts(count: 1, longestSeconds: 2.5), .fair), .init(.longLaps([4, 7]), .fair),
            ])
        #expect(
            long.messages(units: .imperial) == [
                "Positions stopped for 2.5 s while moving.",
                "Laps 4 and 7 are about twice the usual length: the start/finish line was probably missed.",
            ])
    }

    @Test func noPositionsNoVerdict() {
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2],
            columns: [RawColumn(name: "rpm", unit: .rpm, suggestedRole: .rpm, values: [1, 2, 3])])
        let session = SessionBuilder.build(table)
        #expect(session.gpsQuality == nil)
        #expect(session[.gpsRate] == nil)
    }
}
