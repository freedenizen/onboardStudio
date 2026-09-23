import Foundation
import ProjectModel
import TelemetryKit

extension ProjectDetails {
    /// What a data file says about itself (#74): the track and driver its logger recorded and the
    /// day it was made. `circuitName` is the circuit the trace was recognised as, used only when
    /// the file does not name its track — a driver's name for a place beats a database's.
    public static func suggested(by session: TelemetrySession, circuitName: String? = nil) -> ProjectDetails {
        let info = session.info
        return ProjectDetails(
            track: nonEmpty(info.trackName) ?? circuitName ?? "",
            driver: nonEmpty(info.driverName) ?? "",
            date: info.createdAt.map(ProjectDetails.iso) ?? "")
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
