import Foundation
import TelemetryKit

/// What the Analysis view's friction circle reads the laps against (#631): the car's grip in the
/// reference lap's conditions when the logbook knows its session, else the most the session reached.
public struct GripTarget: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// The car's limit from the logbook, as `CarGrip.limit` gives it.
        case car(CarGripLimit)
        /// The reference session's own envelope, for a session the logbook does not know.
        case session
    }

    public var envelope: GripEnvelope
    public var source: Source

    public init(envelope: GripEnvelope, source: Source) {
        self.envelope = envelope
        self.source = source
    }

    /// The car's limit, adjusted as the driver has adjusted it.
    public static func car(_ limit: CarGripLimit) -> GripTarget {
        GripTarget(envelope: limit.limit, source: .car(limit))
    }

    /// The car's limit when there is one, else `session`'s own envelope; `nil` when neither is known.
    public static func choose(car limit: CarGripLimit?, session: GripEnvelope?) -> GripTarget? {
        if let limit { return .car(limit) }
        return session.map { GripTarget(envelope: $0, source: .session) }
    }

    /// The line under the circle: "Dashed: the car's grip, 1.02–1.15 G from 6 sessions, dry".
    public var caption: String {
        switch source {
        case .car(let limit): "Dashed: the car's grip, \(limit.summary)"
        case .session: "Dashed: the most this session reached"
        }
    }

    /// "the car's grip" or "this session's grip", for a sentence about a lap's share of it.
    public var noun: String {
        switch source {
        case .car: "the car's grip"
        case .session: "this session's grip"
        }
    }

    /// The most of the target any of `points` used, 0 at rest and 1 at the limit.
    public func mostUsed(_ points: [(lateral: Double, longitudinal: Double)]) -> Double {
        points.map { envelope.used(lateral: $0.lateral, longitudinal: $0.longitudinal) }.max() ?? 0
    }
}
