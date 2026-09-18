import Foundation
import GPMFKit
import ProjectModel
import TelemetryKit

/// Lines a data input up with a video from timestamps alone: the video's recording start on the
/// wall clock (its GPS clock when it has GoPro telemetry, otherwise the container's creation
/// date) against the data's own clock.
public enum TimestampSync {
    public struct Suggestion: Sendable, Equatable {
        public let sync: SyncSettings
        /// Where the video's start time came from.
        public let videoClock: String
    }

    /// The instant (seconds since 1970) at which the video file's time 0 was recorded.
    public static func recordingStart(of url: URL, info: MediaInfo) -> (epoch: Double, source: String)? {
        if let gps = GoProTelemetry.recordingStartEpoch(of: url) { return (gps, "GoPro GPS clock") }
        if let created = info.creationDate { return (created.timeIntervalSince1970, "file creation time") }
        return nil
    }

    /// Sync settings that show the data at the same wall-clock instant as the video frame. The
    /// video's own sync (trim start, project offset, speed) is honoured so the data follows it.
    public static func suggest(
        data session: TelemetrySession, video: SyncSettings, videoStartEpoch: Double, videoClock: String
    ) -> Suggestion? {
        // Project time p shows video time v = (p − off) × speed + start, i.e. wall clock
        // videoStartEpoch + v. The data must show the same instant, so its start position is the
        // session time at the video's own start position and the rest of the mapping is shared.
        guard let start = session.sessionTime(forEpoch: videoStartEpoch + video.startPositionInInput) else {
            return nil
        }
        return Suggestion(
            sync: SyncSettings(
                startPositionInInput: start, offsetInProject: video.offsetInProject, playSpeed: video.playSpeed),
            videoClock: videoClock)
    }
}
