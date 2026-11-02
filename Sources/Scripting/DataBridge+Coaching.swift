import Foundation
import ProjectModel
import RenderKit
import TelemetryKit

/// `data.reference`, `data.corners` and `data.coaching`: what a Corner Callout knows, for a
/// script that wants to draw its own. All three read the coaching track the compile built for
/// this data input (`ObjectContext.coaching`), which exists when the script mentions them.
extension DataBridge {
    private static let lead = CornerCalloutParams().leadSeconds
    private static let hold = CornerCalloutParams().holdSeconds

    var reference: [String: Any] {
        guard let track = context?.coaching else { return [:] }
        return [
            "label": track.reference.label,
            "phrase": track.referencePhrase,
            "length": track.reference.lengthMeters,
            "duration": track.reference.duration,
        ]
    }

    var corners: [[String: Any]] {
        guard let track = context?.coaching,
            let analysis = track.analyses.min(by: { $0.key < $1.key })?.value
        else { return [] }
        return analysis.corners.map { comparison in
            let corner = comparison.reference.corner
            return [
                "index": comparison.index,
                "label": comparison.label,
                "start": corner.startDistance,
                "end": corner.endDistance,
                "apex": corner.apexDistance,
            ]
        }
    }

    var coaching: Any? {
        guard let context, let track = context.coaching,
            let moment = track.moment(
                atInputTime: context.inputTime(time), leadSeconds: Self.lead, holdSeconds: Self.hold)
        else { return NSNull() }
        let units: CoachingUnits = context.speedUnit == .mph ? .imperial : .metric
        let comparison = moment.comparison
        var result: [String: Any] = [
            "index": comparison.index,
            "label": comparison.label,
            "lapNumber": moment.lap.number,
            "phase": moment.phase?.rawValue ?? NSNull(),
            "secondsToBrake": moment.secondsToBrakePoint,
            "held": moment.isHeld,
            "timeLost": comparison.timeLost,
            "worstPhase": comparison.worstPhase?.rawValue ?? NSNull(),
            "phaseLoss": Dictionary(
                uniqueKeysWithValues: CornerPhase.allCases.map { ($0.rawValue, comparison.phaseLoss[$0] ?? 0) }),
            "lap": Self.metrics(comparison.lap),
            "reference": Self.metrics(comparison.reference),
        ]
        let card = CornerCalloutRenderer.card(
            for: comparison, analysis: moment.analysis, params: CornerCalloutParams(), units: units)
        result["headline"] = card?.headline ?? NSNull()
        result["evidence"] = card?.evidence ?? []
        result["suggestion"] = card?.suggestion ?? NSNull()
        return result
    }

    /// One lap's reading of a corner. Speeds in m/s; distances in metres before (+) the apex
    /// for the brake point, after (+) the apex for the rest, as `CornerMetrics` keeps them.
    private static func metrics(_ metrics: CornerMetrics) -> [String: Any] {
        func value(_ number: Double?) -> Any { number ?? NSNull() }
        return [
            "brakePoint": value(metrics.brakePointMeters),
            "brakeSource": metrics.brakeSource?.rawValue ?? NSNull(),
            "peakBrakingG": value(metrics.peakBrakingG),
            "brakeRelease": value(metrics.brakeReleaseMeters),
            "trailBraking": value(metrics.trailBrakingMeters),
            "entrySpeed": metrics.entrySpeed,
            "minimumSpeed": metrics.minimumSpeed,
            "minimumSpeedAt": metrics.minimumSpeedMeters,
            "exitSpeed": metrics.exitSpeed,
            "throttlePickup": value(metrics.throttlePickupMeters),
            "throttleSource": metrics.throttleSource?.rawValue ?? NSNull(),
            "fullThrottle": value(metrics.fullThrottleMeters),
            "coasting": value(metrics.coastingSeconds),
            "peakLateralG": value(metrics.peakLateralG),
            "timeInCorner": metrics.timeInCorner,
            "steeringSmoothness": value(metrics.steeringSmoothness),
        ]
    }
}
