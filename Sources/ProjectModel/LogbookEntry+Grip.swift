import Foundation
import TelemetryKit

/// What a session showed of the car's grip (#558), kept on its Logbook entry: the envelope its
/// laps reached, and its best lap's G, so the lap can be read again against the car's limit as the
/// logbook learns it.
public struct GripRecord: Hashable, Codable, Sendable {
    public var envelope: GripEnvelope
    public var bestLap: GripTrace?

    public init(envelope: GripEnvelope, bestLap: GripTrace?) {
        self.envelope = envelope
        self.bestLap = bestLap
    }

    /// `session`'s; `nil` without G to read (no laps, no position, a straight-line log).
    public init?(session: TelemetrySession) {
        guard let envelope = GripEnvelope.measure(session) else { return nil }
        self.envelope = envelope
        bestLap = LapDeltas.sessionBest(in: session).flatMap { lap in
            LapProfile(lap: lap, in: session).flatMap { profile in
                let corners = session.agreedCorners(of: profile)
                return GripTrace(profile, corners: corners, labels: session.cornerNames(for: corners).map(\.label))
            }
        }
    }
}

extension LogbookEntry {
    /// The reading `grip` is from. 1 (#558): the first.
    public static let gripMeasurement = 1

    /// Whether its grip is still to be read: it was entered before it was.
    public var needsGripReading: Bool { gripMeasurement < Self.gripMeasurement }

    /// Something kept with the entry is from before it was read: sectors, GPS or grip.
    public var needsAReading: Bool { needsSplitReading || needsGPSReading || needsGripReading }

    public mutating func readGrip(of session: TelemetrySession) {
        grip = GripRecord(session: session)
        gripMeasurement = Self.gripMeasurement
    }
}
