import Foundation
import Testing

@testable import TelemetryKit

/// #562: a second logger lined up with the first by a channel both recorded.
@Suite("Lining up a second data file (#562)")
struct DataAlignmentTests {
    /// Revs that rise and fall as a lap's would, never repeating exactly.
    static func rpm(_ t: Double) -> Double {
        4_500 + 1_800 * sin(t / 3.1) + 900 * sin(t / 1.27 + 1) + 400 * sin(t / 0.53)
    }

    static func session(
        _ role: ChannelRole, unit: TelemetryUnit, from: Double, to: Double, step: Double, shift: Double = 0,
        scale: Double = 1, value: (Double) -> Double = rpm
    ) -> TelemetrySession {
        let times = Array(stride(from: from, to: to, by: step))
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: times,
            columns: [
                RawColumn(
                    name: role.identifier, unit: unit, suggestedRole: role,
                    values: times.map { value($0 + shift) * scale })
            ])
        return SessionBuilder.build(table)
    }

    @Test func anECULogIsLinedUpByItsRPM() throws {
        let gps = Self.session(.rpm, unit: .rpm, from: 0, to: 300, step: 0.1)
        // The ECU started 37.5 s into the GPS logger's session, on its own clock, at 20 Hz.
        let ecu = Self.session(.rpm, unit: .rpm, from: 0, to: 200, step: 0.05, shift: 37.5)
        let result = try #require(DataAlignment.align(ecu, to: gps))
        #expect(result.role == .rpm)
        #expect(abs(result.offset - 37.5) < 0.15)
        #expect(result.isConfident)
    }

    @Test func aLongerSecondFileFitsTheOtherWay() throws {
        let short = Self.session(.rpm, unit: .rpm, from: 0, to: 120, step: 0.1, shift: 60)
        let long = Self.session(.rpm, unit: .rpm, from: 0, to: 400, step: 0.1)
        let result = try #require(DataAlignment.align(long, to: short))
        // long's second 60 is short's second 0.
        #expect(abs(result.offset + 60) < 0.15)
    }

    @Test func speedInAnotherUnitStillLinesUp() throws {
        let speed: (Double) -> Double = { 30 + 12 * sin($0 / 4) + 5 * sin($0 / 1.3) }
        let gps = Self.session(.speed, unit: .metersPerSecond, from: 0, to: 240, step: 0.1, value: speed)
        let ecu = Self.session(
            .speed, unit: .kilometersPerHour, from: 0, to: 150, step: 0.1, shift: 20, scale: 3.6, value: speed)
        let result = try #require(DataAlignment.align(ecu, to: gps))
        #expect(abs(result.offset - 20) < 0.15)
    }

    @Test func nothingSharedOrFlatSaysNothing() {
        let rpm = Self.session(.rpm, unit: .rpm, from: 0, to: 100, step: 0.1)
        let throttle = Self.session(.throttle, unit: .percent, from: 0, to: 100, step: 0.1) { _ in 50 }
        #expect(DataAlignment.sharedRoles(rpm, throttle).isEmpty)
        #expect(DataAlignment.align(throttle, to: rpm) == nil)
        let flat = Self.session(.rpm, unit: .rpm, from: 0, to: 100, step: 0.1) { _ in 3_000 }
        #expect(DataAlignment.align(flat, to: rpm) == nil)
    }

    @Test func rpmComesFirstAmongWhatTheyShare() {
        let a = Self.session(.rpm, unit: .rpm, from: 0, to: 10, step: 0.1)
        #expect(DataAlignment.sharedRoles(a, a) == [.rpm])
    }
}
