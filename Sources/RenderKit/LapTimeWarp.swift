import Foundation
import ProjectModel
import TelemetryKit

/// Project time on the lap playing → the project time at which the compared lap was as far round
/// its own lap (#154). What keeps the second picture of a lap comparison level with the first, and
/// what the objects that follow the compared lap read their data through.
///
/// "As far round" is the same *fraction* of the lap, not the same metres: two sessions' GPS rarely
/// agree on a lap's length to the metre, and a comparison across days should still meet at the line.
///
/// Piecewise linear between knots a fraction of a second apart. Before the lap and after it the
/// compared side runs on at normal speed from where it was, so the run-up and run-out still play.
public struct LapTimeWarp: Sendable, Equatable {
    /// Project times along the lap playing, strictly increasing, first at its start and last at its end.
    public let lapTimes: [Double]
    /// For each, the project time at which the compared lap was as far round; never decreasing.
    public let comparedTimes: [Double]

    public var lapStart: Double { lapTimes[0] }
    public var lapEnd: Double { lapTimes[lapTimes.count - 1] }
    public var comparedStart: Double { comparedTimes[0] }
    public var comparedEnd: Double { comparedTimes[comparedTimes.count - 1] }
    public var lapDuration: Double { lapEnd - lapStart }
    public var comparedDuration: Double { comparedEnd - comparedStart }

    /// Knots every `step` seconds of `lap`'s data, from each lap's own session and sync. `nil`
    /// without a distance channel on either side, or unless both laps have ended and covered ground.
    public init?(
        lap: Lap, in session: TelemetrySession, sync: SyncSettings, compared: Lap, in comparedSession: TelemetrySession,
        comparedSync: SyncSettings, step: Double = 0.25
    ) {
        guard let distance = session[.distance], let comparedDistance = comparedSession[.distance],
            let end = lap.end, let comparedEnd = compared.end, end > lap.start, comparedEnd > compared.start,
            let from = distance.value(at: lap.start), let to = distance.value(at: end),
            let comparedFrom = comparedDistance.value(at: compared.start),
            let comparedTo = comparedDistance.value(at: comparedEnd), to > from, comparedTo > comparedFrom
        else { return nil }
        let length = to - from
        let comparedLength = comparedTo - comparedFrom
        var lapTimes: [Double] = []
        var comparedTimes: [Double] = []
        let count = max(Int(((end - lap.start) / max(step, 0.01)).rounded(.up)), 1)
        for index in 0...count {
            let time = index == count ? end : lap.start + Double(index) * step
            let fraction: Double
            if index == 0 {
                fraction = 0
            } else if index == count {
                fraction = 1
            } else {
                fraction = min(max(((distance.value(at: time) ?? from) - from) / length, 0), 1)
            }
            let comparedTime: Double
            switch fraction {
            case 0: comparedTime = compared.start
            case 1: comparedTime = comparedEnd
            default:
                comparedTime =
                    LapComparison.time(
                        atDistance: comparedFrom + fraction * comparedLength, in: comparedDistance,
                        between: compared.start, and: comparedEnd) ?? comparedEnd
            }
            let projectTime = sync.projectTime(forInputTime: time)
            let comparedProjectTime = max(
                comparedSync.projectTime(forInputTime: comparedTime), comparedTimes.last ?? -.infinity)
            if let last = lapTimes.last, projectTime <= last { continue }
            lapTimes.append(projectTime)
            comparedTimes.append(comparedProjectTime)
        }
        guard lapTimes.count >= 2 else { return nil }
        self.lapTimes = lapTimes
        self.comparedTimes = comparedTimes
    }

    /// The warp a project's lap comparison describes, from its loaded sessions; `nil` when it is not
    /// comparing laps or the laps cannot be matched.
    public init?(_ settings: LapComparisonSettings?, project: Project, sessions: [InputID: TelemetrySession]) {
        guard let settings, let session = sessions[settings.lap.dataInputID],
            let comparedSession = sessions[settings.comparedLap.dataInputID],
            let input = project.input(settings.lap.dataInputID),
            let comparedInput = project.input(settings.comparedLap.dataInputID),
            let lap = session.laps.first(where: { $0.number == settings.lap.lap }),
            let compared = comparedSession.laps.first(where: { $0.number == settings.comparedLap.lap })
        else { return nil }
        self.init(
            lap: lap, in: session, sync: input.sync, compared: compared, in: comparedSession,
            comparedSync: comparedInput.sync)
    }

    /// The project time at which the compared lap was as far round as the lap playing is at `time`.
    public func comparedTime(at time: Double) -> Double {
        if time <= lapStart { return comparedStart + (time - lapStart) }
        if time >= lapEnd { return comparedEnd + (time - lapEnd) }
        var low = 0
        var high = lapTimes.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if lapTimes[mid] <= time { low = mid } else { high = mid }
        }
        let fraction = (time - lapTimes[low]) / (lapTimes[high] - lapTimes[low])
        return comparedTimes[low] + (comparedTimes[high] - comparedTimes[low]) * fraction
    }

    /// Seconds the lap playing is behind (+) or ahead of (−) the compared lap at the same point
    /// round it; `nil` outside the lap.
    public func delta(at time: Double) -> Double? {
        guard time >= lapStart, time <= lapEnd else { return nil }
        return (time - lapStart) - (comparedTime(at: time) - comparedStart)
    }
}
