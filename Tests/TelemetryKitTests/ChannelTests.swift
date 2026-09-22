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

    @Test(arguments: [("bar", TelemetryUnit.bar), ("BAR", .bar), ("bars", .bar), ("kPa", .kilopascal)])
    func parsesPressureSpellings(text: String, expected: TelemetryUnit) {
        #expect(TelemetryUnit(parsing: text) == expected)
    }

    /// The milestone's own example: a brake channel logged in kPa, shown in bar.
    @Test func convertsThroughThePressureFamily() throws {
        #expect(try #require(TelemetryUnit.kilopascal.convert(100, to: .bar)).isApproximately(1))
        #expect(try #require(TelemetryUnit.bar.convert(1, to: .kilopascal)).isApproximately(100))
        #expect(try #require(TelemetryUnit.bar.convert(1, to: .psi)).isApproximately(14.503_773_8))
        #expect(try #require(TelemetryUnit.psi.convert(14.503_773_8, to: .bar)).isApproximately(1))
    }

    /// Temperature is the case a bare multiplier gets wrong: 20 °C is 68 °F, not 36 °F.
    @Test func convertsTemperatureWithItsOffset() throws {
        #expect(try #require(TelemetryUnit.celsius.convert(20, to: .fahrenheit)).isApproximately(68))
        #expect(try #require(TelemetryUnit.celsius.convert(-40, to: .fahrenheit)).isApproximately(-40))
        #expect(try #require(TelemetryUnit.fahrenheit.convert(212, to: .celsius)).isApproximately(100))
    }

    /// `conversionFactor` must refuse the offset conversions rather than answer 1.8.
    @Test func factorRefusesOffsetConversions() {
        #expect(TelemetryUnit.celsius.conversionFactor(to: .fahrenheit) == nil)
        #expect(TelemetryUnit.fahrenheit.conversionFactor(to: .celsius) == nil)
        #expect(TelemetryUnit.celsius.conversionFactor(to: .celsius) == 1)
    }

    @Test func unitsOnlyConvertWithinTheirFamily() {
        #expect(TelemetryUnit.bar.convert(1, to: .percent) == nil)
        #expect(TelemetryUnit.celsius.convert(1, to: .kilopascal) == nil)
        #expect(TelemetryUnit.custom("bpm").convert(1, to: .rpm) == nil)
        #expect(TelemetryUnit.none.convert(1, to: .meters) == nil)
    }

    /// #89: a picker offers the units the attribute can actually be shown in, and no others.
    @Test func convertibleUnitsAreTheFamily() {
        #expect(TelemetryUnit.kilopascal.convertibleUnits == [.kilopascal, .bar, .psi])
        #expect(TelemetryUnit.percent.convertibleUnits == [.percent])
        #expect(TelemetryUnit.custom("bpm").convertibleUnits.isEmpty)
        #expect(TelemetryUnit.none.family == nil)
    }

    /// Every unit with a family converts to that family's base, and the families partition the
    /// enum: nothing claims a family it cannot convert within.
    @Test func everyFamilyMemberConvertsToItsBase() {
        for family in UnitFamily.allCases {
            #expect(family.units.contains(family.base), "\(family) omits its own base unit")
            for unit in family.units {
                #expect(
                    unit.family == family,
                    "\(unit) is listed under \(family) but claims \(String(describing: unit.family))")
                #expect(unit.convert(1, to: family.base) != nil, "\(unit) does not convert to \(family.base)")
            }
        }
    }

    @Test func channelConvertsItsValues() {
        let channel = Channel(
            role: .canbus("coolant"), name: "Coolant", unit: .celsius, times: [0, 1], values: [0, 100])
        let converted = channel.converted(to: .fahrenheit)
        #expect(converted.unit == .fahrenheit)
        #expect(converted.values[0].isApproximately(32))
        #expect(converted.values[1].isApproximately(212))
        #expect(channel.converted(to: .meters).unit == .celsius)
    }
}

extension Double {
    fileprivate func isApproximately(_ other: Double, tolerance: Double = 1e-6) -> Bool {
        abs(self - other) <= tolerance
    }
}
