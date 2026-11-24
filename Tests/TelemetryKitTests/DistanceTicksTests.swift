import Testing

@testable import TelemetryKit

/// The marks on a distance axis (#669).
@Suite("Distance axis marks (#669)")
struct DistanceTicksTests {
    @Test func aLapInFeetIsMarkedAtRoundFeet() {
        // A lap of about three kilometres: marked every 2,000 ft, where a mark every kilometre
        // was written 3,281, 6,562, 9,843.
        let marks = DistanceTicks.positions(in: 0...3_100, metresPerUnit: 0.3048)
        let feet = marks.map { ($0 / 0.3048).rounded() }
        #expect(feet == [0, 2_000, 4_000, 6_000, 8_000, 10_000])
    }

    @Test func aLapInMetresIsMarkedAtRoundMetres() {
        #expect(DistanceTicks.positions(in: 0...3_100, metresPerUnit: 1) == [0, 1_000, 2_000, 3_000])
    }

    @Test func aCornerZoomedInOnStartsAtTheFirstRoundMarkInside() {
        let marks = DistanceTicks.positions(in: 1_240...1_610, metresPerUnit: 1)
        #expect(marks == [1_300, 1_400, 1_500, 1_600])
        #expect(marks.allSatisfy { (1_240...1_610).contains($0) })
    }

    @Test func nothingToMarkIsNoMarks() {
        #expect(DistanceTicks.positions(in: 5...5, metresPerUnit: 1).isEmpty)
        #expect(DistanceTicks.positions(in: 0...100, metresPerUnit: 0).isEmpty)
    }
}
