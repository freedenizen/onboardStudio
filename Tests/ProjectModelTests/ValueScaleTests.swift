import Testing

@testable import ProjectModel

/// The box beside each slider shows and takes the value as the user thinks of it (#266).
@Suite struct ValueScaleTests {
    @Test func percentReadsAsWholeNumbers() {
        #expect(ValueScale.percent.shown(0.12) == 12)
        #expect(ValueScale.percent.stored(12, in: 0...0.45) == 0.12)
        #expect(ValueScale.percent.shown(0...0.45) == 0...45)
    }

    @Test func typedValuesAreHeldToTheSlidersRange() {
        #expect(ValueScale.percent.stored(500, in: 0...0.45) == 0.45)
        #expect(ValueScale.percent.stored(-3, in: 0...0.45) == 0)
        #expect(ValueScale.plain().stored(200, in: -180...180) == 180)
    }

    @Test func aZoomReadsAsWhatItAdds() {
        let scale = ValueScale.percentAboveOne
        #expect(abs(scale.shown(1.08) - 8) < 1e-9)
        #expect(abs(scale.stored(8, in: 1...1.5) - 1.08) < 1e-9)
        #expect(scale.shown(1...1.5) == 0...50)
    }

    @Test func arrowKeysStepAsTheSliderDoes() {
        #expect(ValueScale.percent.keyStep(sliderStep: nil) == 1)
        #expect(ValueScale.percent.keyStep(sliderStep: 0.05) == 5)
        #expect(ValueScale.plain(fractionDigits: 1).keyStep(sliderStep: nil) == 0.1)
        #expect(ValueScale.plain().keyStep(sliderStep: 1) == 1)
    }

    @Test func aValueThatIsNotANumberFallsToTheBottom() {
        #expect(ValueScale.percent.stored(.nan, in: 0.2...1) == 0.2)
    }

    @Test func newGraphsPutNowInTheMiddle() {
        #expect(GraphParams(series: []).playheadPosition == GraphParams.middlePlayheadPosition)
        #expect(GraphParams.middlePlayheadPosition == 0.5)
    }
}
