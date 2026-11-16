import Foundation
import TelemetryKit

/// How far a session's positions can be trusted (#555), kept on its Logbook entry so the
/// Logbook can say so without reading the file again.
extension LogbookEntry {
    /// The reading `gps` is from. 1 (#555): the first.
    public static let gpsMeasurement = 1

    /// Whether its positions are still to be judged: it was entered before they were. The Logbook
    /// reads them from the file when it next shows the session.
    public var needsGPSReading: Bool { gpsMeasurement < Self.gpsMeasurement }

    /// Keeps what `session` says about its positions; `nil` for a file without them.
    public mutating func readGPS(of session: TelemetrySession) {
        gps = session.gpsQuality
        gpsMeasurement = Self.gpsMeasurement
    }

    /// For sorting by the GPS column: good first, a session not yet judged last.
    public var gpsRank: Int { gps.map { $0.rated(with: .app).rating.rawValue } ?? (needsGPSReading ? 4 : 3) }
}
