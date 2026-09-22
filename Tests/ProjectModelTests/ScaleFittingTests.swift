import Testing

@testable import ProjectModel

@Suite("Fitting a scale to the data")
struct ScaleFittingTests {
    func summary(_ identifier: String, unit: String = "", _ low: Double?, _ high: Double?) -> ChannelSummary {
        ChannelSummary(identifier: identifier, name: identifier, unit: unit, minValue: low, maxValue: high)
    }

    // MARK: - The bounds themselves

    @Test func aChannelThatNeverGoesNegativeStartsAtZero() throws {
        let bounds = try #require(summary("brake", unit: "kPa", 12, 1873).suggestedBounds)
        #expect(bounds.min == 0)
        #expect(bounds.max == 1900)
    }

    @Test func aChannelThatStraddlesZeroIsSymmetric() throws {
        let bounds = try #require(summary("lateralG", unit: "G", -1.24, 1.37).suggestedBounds)
        #expect(bounds.min == -bounds.max)
        #expect(bounds.max >= 1.37)
        #expect(bounds.max < 1.5)
    }

    @Test func theScaleAlwaysContainsTheData() {
        for (low, high) in [(0.0, 100.0), (12.0, 1873.0), (-1.24, 1.37), (-40.0, -5.0), (0.0, 0.7)] {
            guard let bounds = summary("x", low, high).suggestedBounds else {
                Issue.record("No bounds for \(low)…\(high)")
                continue
            }
            #expect(bounds.min <= low, "\(low)…\(high) lost its floor")
            #expect(bounds.max >= high, "\(low)…\(high) lost its ceiling")
        }
    }

    /// A guess is only worth making when the data supports one.
    @Test func anUnknownOrFlatRangeSuggestsNothing() {
        #expect(summary("x", nil, nil).suggestedBounds == nil)
        #expect(summary("x", 5, 5).suggestedBounds == nil)
        #expect(summary("x", 10, 2).suggestedBounds == nil)
        #expect(summary("x", .infinity, 1).suggestedBounds == nil)
    }

    // MARK: - What an object is created with

    /// The case #111 makes routine: Brake read in kPa, and a bar that would otherwise be a
    /// percentage scale pinned at full for the whole lap.
    @Test func aBarTakesTheScaleAndUnitOfItsChannel() {
        let bar = BarParams(channel: "brake", label: "BRAKE", unitLabel: "%")
        let fitted = bar.fitted(to: [summary("brake", unit: "kPa", 0, 1873)])
        #expect(fitted.minValue == 0)
        #expect(fitted.maxValue == 1900)
        #expect(fitted.unitLabel == "kPa")
    }

    @Test func aGaugeTakesTheScaleAndRedrawsItsTicks() {
        let gauge = GaugeParams(
            channel: "throttle", title: "THROTTLE", minValue: 0, maxValue: 100, unitLabel: "%",
            majorTick: 25, minorTick: 5)
        let fitted = gauge.fitted(to: [summary("throttle", unit: "%", 0, 100)])
        #expect(fitted.maxValue == 100)
        #expect(fitted.majorTick > 0)
        #expect(fitted.minorTick > 0)
        #expect(fitted.majorTick >= fitted.minorTick)
    }

    /// A channel the object does not read, or one the data does not have, leaves it alone.
    @Test func anUnknownChannelChangesNothing() {
        let bar = BarParams(channel: "brake", label: "BRAKE", unitLabel: "%")
        #expect(bar.fitted(to: [summary("throttle", unit: "%", 0, 100)]) == bar)
        #expect(bar.fitted(to: []) == bar)
    }

    /// An empty unit leaves the label alone rather than blanking a label somebody wrote.
    @Test func aChannelWithNoUnitLeavesTheLabel() {
        let bar = BarParams(channel: "aux:x", label: "X", unitLabel: "%")
        #expect(bar.fitted(to: [summary("aux:x", 0, 40)]).unitLabel == "%")
    }

    /// A redline at 6500 of 8000 is a statement about the scale it was drawn against; moving the
    /// scale underneath it would leave the zone somewhere its author never put it.
    @Test func zonesPinTheScaleTheyWereDrawnAgainst() {
        let tacho = GaugeParams.tachometer()
        #expect(tacho.fitted(to: [summary("rpm", unit: "rpm", 800, 7300)]) == tacho)

        let delta = BarParams(
            channel: "lapDelta", label: "Δ", minValue: -2, maxValue: 2,
            zones: [GaugeZone(from: -2, to: 0, color: .red)])
        #expect(delta.fitted(to: [summary("lapDelta", unit: "s", -0.4, 0.9)]) == delta)
    }

    /// Speed is stored in m/s and drawn in the object's speed unit, so a scale fitted to the
    /// stored range would be wrong by exactly that factor — a 0…60 dial for a 130 mph car.
    @Test func aSpeedGaugeKeepsItsTemplateScale() {
        let speedo = GaugeParams.speedometer()
        #expect(speedo.fitted(to: [summary("speed", unit: "m/s", 0, 58)]) == speedo)
        #expect(summary("speed", 0, 58).isConvertedForDisplay)
        #expect(!summary("brake", 0, 58).isConvertedForDisplay)
    }

    @Test func ticksDivideTheScaleIntoRoundNumbers() {
        #expect(GaugeParams.tick(over: 100, parts: 5) == 20)
        #expect(GaugeParams.tick(over: 1900, parts: 5) == 500)
        #expect(GaugeParams.tick(over: 0, parts: 5) == 1)
    }
}
