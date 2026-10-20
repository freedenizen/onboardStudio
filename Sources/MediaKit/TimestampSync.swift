import Foundation
import GPMFKit
import Importers
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
        // A DJI SRT log is stamped per frame from the video's first frame, so its clock is the video's.
        if let companion = info.companion, companion.importerID == DJISRTImporter.id,
            let session = try? FormatDetector.importSession(at: companion.url), let created = session.info.createdAt
        {
            return (created.timeIntervalSince1970, "DJI SRT clock")
        }
        if let sony = info.sidecarCreationDate { return (sony.timeIntervalSince1970, "Sony XML sidecar") }
        if let created = info.creationDate { return (created.timeIntervalSince1970, "file creation time") }
        return nil
    }

    /// How far apart the video and the data are on their clocks: `nil` when they overlap, the
    /// seconds from the end of the log to the start of the video when the video comes after it
    /// (positive), or from the end of the video to the start of the log when it comes before
    /// (negative). A camera whose clock was never set reads days off, and lining the data up with
    /// that clock leaves nothing to show (#311).
    ///
    /// `videoDuration` should be the longest the camera could have been running — every chapter
    /// of the recording — so a log that starts in a later chapter still counts as overlapping.
    public static func clockGap(data session: TelemetrySession, videoStartEpoch: Double, videoDuration: Double)
        -> Double?
    {
        guard let range = session.timeRange, let dataStart = session.epoch(forSessionTime: range.lowerBound),
            let dataEnd = session.epoch(forSessionTime: range.upperBound)
        else { return nil }
        let videoEnd = videoStartEpoch + max(videoDuration, 0)
        if videoStartEpoch > dataEnd { return videoStartEpoch - dataEnd }
        if videoEnd < dataStart { return videoEnd - dataStart }
        return nil
    }

    /// Sync settings that show the data at the same wall-clock instant as the video frame. The
    /// video's own sync (trim start, project offset, speed) is honoured so the data follows it.
    /// `nil` when the clocks put the video and the data apart (see `clockGap`), as well as when
    /// the data has no clock.
    public static func suggest(
        data session: TelemetrySession, video: SyncSettings, videoStartEpoch: Double, videoDuration: Double,
        videoClock: String
    ) -> Suggestion? {
        guard clockGap(data: session, videoStartEpoch: videoStartEpoch, videoDuration: videoDuration) == nil else {
            return nil
        }
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
