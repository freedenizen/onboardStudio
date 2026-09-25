import Testing

@testable import MediaKit

/// Long jobs report progress per frame; the interface hears of it only when it has moved (#279).
@Suite struct ProgressThrottleTests {
    @Test func aThousandFramesAreAboutAThousandthEach() {
        var throttle = ProgressThrottle(step: 0.01)
        let reported = (0...10_000).map { Double($0) / 10_000 }.filter { throttle.shouldReport($0) }
        #expect(reported.count == 101)
        #expect(reported.first == 0)
        #expect(reported.last == 1)
    }

    @Test func theEndIsAlwaysReported() {
        var throttle = ProgressThrottle(step: 0.1)
        let reports = [0.95, 1, 1].map { throttle.shouldReport($0) }
        #expect(reports == [true, true, false])
    }

    @Test func aStepBackIsReported() {
        var throttle = ProgressThrottle(step: 0.1)
        let reports = [0.5, 0.45, 0.3].map { throttle.shouldReport($0) }
        #expect(reports == [true, false, true])
    }
}
