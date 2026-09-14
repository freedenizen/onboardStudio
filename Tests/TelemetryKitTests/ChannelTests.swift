import Testing

@testable import TelemetryKit

@Suite("Channel interpolation")
struct ChannelTests {
    let linear = Channel(
        role: .speed, name: "Speed", unit: .metersPerSecond, times: [0, 1, 2, 4], values: [0, 10, 20, 40])
    let stepped = Channel(
        role: .gear, name: "Gear", unit: .count, times: [0, 1, 2], values: [1, 2, 3], interpolation: .step)

    @Test func exactSampleTimesReturnStoredValues() {
        #expect(linear.value(at: 1) == 10)
        #expect(linear.value(at: 4) == 40)
    }

    @Test func linearInterpolatesBetweenSamples() {
        #expect(linear.value(at: 0.5) == 5)
        #expect(linear.value(at: 3) == 30)
    }

    @Test func clampsOutsideRecordedRange() {
        #expect(linear.value(at: -5) == 0)
        #expect(linear.value(at: 100) == 40)
    }

    @Test func stepHoldsPreviousValue() {
        #expect(stepped.value(at: 0.99) == 1)
        #expect(stepped.value(at: 1.0) == 2)
        #expect(stepped.value(at: 1.5) == 2)
    }

    @Test func emptyChannelReturnsNil() {
        let empty = Channel(role: .rpm, name: "RPM", unit: .rpm, times: [], values: [])
        #expect(empty.value(at: 0) == nil)
        #expect(empty.sampleRate == nil)
    }

    @Test func sampleRateAndExtremes() {
        #expect(linear.sampleRate == 0.75)
        #expect(linear.minValue == 0)
        #expect(linear.maxValue == 40)
    }

    @Test func unitConversionToCanonical() {
        let kph = Channel(role: .speed, name: "KPH", unit: .kilometersPerHour, times: [0], values: [36])
        let converted = kph.convertedToCanonicalUnit()
        #expect(converted.unit == .metersPerSecond)
        #expect(abs(converted.values[0] - 10) < 1e-9)
        let mph = Channel(role: .speed, name: "MPH", unit: .milesPerHour, times: [0], values: [100])
        #expect(abs(mph.convertedToCanonicalUnit().values[0] - 44.704) < 1e-9)
    }

    @Test func binarySearchFindsInsertionPoint() {
        let sorted: [Double] = [1, 3, 5, 7]
        #expect(sorted.firstIndex(atOrAfter: 0) == 0)
        #expect(sorted.firstIndex(atOrAfter: 3) == 1)
        #expect(sorted.firstIndex(atOrAfter: 4) == 2)
        #expect(sorted.firstIndex(atOrAfter: 8) == 4)
    }
}

@Suite("Units")
struct UnitTests {
    @Test(arguments: [
        ("km/h", TelemetryUnit.kilometersPerHour), ("MPH", .milesPerHour), ("m/s", .metersPerSecond), ("G", .gForce),
        ("%", .percent), ("", .none), ("bpm", .custom("bpm")),
    ])
    func parsesCommonSpellings(text: String, expected: TelemetryUnit) {
        #expect(TelemetryUnit(parsing: text) == expected)
    }

    @Test func incompatibleUnitsHaveNoConversion() {
        #expect(TelemetryUnit.gForce.conversionFactor(to: .meters) == nil)
        #expect(TelemetryUnit.feet.conversionFactor(to: .meters) == 0.3048)
    }
}
