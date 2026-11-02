import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// A timer measuring against the logbook's personal best (#351).
@Suite("Personal-best timer")
struct PersonalBestTimerTests {
    static let session = CoachingTrackSession.session

    func context(personalBest: LapProfile?) -> ObjectContext {
        ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: TelemetrySampler(session: Self.session),
            sync: .identity, cache: RenderCache(), personalBest: personalBest)
    }

    @Test func theDeltaIsAgainstThePersonalBestAtTheSameDistance() throws {
        let session = Self.session
        let best = try #require(session.laps.first { $0.number == 4 })
        let slow = session.laps[1]
        let pb = try #require(LapProfile(lap: best, in: session))
        let time = slow.start + 20
        let sample = TelemetrySampler(session: session).sample(at: time)
        let with = TimerRenderer(
            context: context(personalBest: pb), params: TimerParams(mode: .deltaToBest, deltaReference: .personalBest))
        let delta = with.readout(sample: sample, projectTime: time)
        #expect(delta.text.hasPrefix("+"), "the slow lap is behind the best: \(delta.text)")
        #expect(delta.color == TimerParams().behindColor)
        let projected = TimerRenderer(
            context: context(personalBest: pb), params: TimerParams(mode: .projectedLap, deltaReference: .personalBest))
        let text = projected.readout(sample: sample, projectTime: time).text
        #expect(text.hasPrefix("0:4"), "the best lap's time plus the gap: \(text)")
        // The same slow lap read against itself as the personal best is level.
        let own = try #require(LapProfile(lap: slow, in: session))
        let level = TimerRenderer(
            context: context(personalBest: own), params: TimerParams(mode: .deltaToBest, deltaReference: .personalBest))
        #expect(level.readout(sample: sample, projectTime: time).text == "0.00")
        // Without a personal best the timer measures the session best, as it always did.
        let fallback = TimerRenderer(
            context: context(personalBest: nil), params: TimerParams(mode: .deltaToBest, deltaReference: .personalBest))
        let fallbackText = fallback.readout(sample: sample, projectTime: time).text
        #expect(fallbackText != "--.--" && fallbackText.hasPrefix("+"), Comment(rawValue: fallbackText))
    }
}
