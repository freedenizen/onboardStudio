import Foundation

/// Snaps a dragged time to nearby edges (clip starts and ends, the playhead, zero) the way an
/// editor's magnet does: the nearest target within `tolerance` wins.
public struct TimelineSnapping: Sendable {
    public var targets: [Double]
    public var tolerance: Double

    public init(targets: [Double], tolerance: Double) {
        self.targets = targets
        self.tolerance = tolerance
    }

    /// `time`, or the closest target within tolerance.
    public func snap(_ time: Double) -> Double {
        var bestTarget = time
        var bestDistance = Double.infinity
        for target in targets {
            let distance = abs(target - time)
            guard distance <= tolerance, distance < bestDistance else { continue }
            bestTarget = target
            bestDistance = distance
        }
        return bestTarget
    }

    /// Snaps a clip that spans `length` seconds: either its start or its end may land on a target.
    public func snapSpan(start: Double, length: Double) -> Double {
        let snappedStart = snap(start)
        if snappedStart != start { return snappedStart }
        let snappedEnd = snap(start + length)
        return snappedEnd != start + length ? snappedEnd - length : start
    }
}

/// The arithmetic behind dragging a video bar's edges on the timeline.
public enum VideoTrimming {
    /// Moves the head of a video to project time `time` keeping the picture where it was: the
    /// start position in the file advances by the same amount (scaled by play speed).
    public static func headTrimmed(_ sync: SyncSettings, toProjectTime time: Double) -> SyncSettings {
        let delta = max(0, time) - sync.offsetInProject
        var result = sync
        result.offsetInProject = max(0, sync.offsetInProject + delta)
        result.startPositionInInput = max(0, sync.startPositionInInput + delta * sync.playSpeed)
        return result
    }

    /// The trim end (file seconds) that makes a video stop at project time `time`, or `nil` when
    /// that is at or beyond the file's end (`fullDuration`), meaning "no trim".
    public static func tailTrimmed(
        _ sync: SyncSettings, trim: TrimRange, toProjectTime time: Double, fullDuration: Double?
    ) -> Double? {
        let start = max(trim.start ?? 0, sync.startPositionInInput)
        let fileEnd = start + max(0.1, time - sync.offsetInProject) * sync.playSpeed
        if let full = fullDuration, fileEnd >= full - 0.05 { return nil }
        return fileEnd
    }
}

extension VideoTrimming {
    /// How a video's two halves are timed when it is cut at project time `time`.
    ///
    /// The first half keeps its place and stops at the cut; the second starts at the cut, both on
    /// the timeline and in the file, so the picture runs on unbroken across the join. Speed and
    /// any existing end trim carry over untouched.
    public struct Split: Hashable, Sendable {
        /// Trim end for the first half, in file seconds.
        public let firstEnd: Double
        /// Timing for the second half.
        public let secondSync: SyncSettings
        /// Trim for the second half: the original end, with the start moved to the cut.
        public let secondTrim: TrimRange
    }

    /// Returns `nil` when the cut is not strictly inside the input, where there is no second half
    /// to make and splitting would only produce an empty one.
    ///
    /// `fullStart` is where the input's own content begins in file time, bounding the cut from
    /// below as `fullDuration` bounds it from above. It is 0 for a video, but a data session's
    /// first sample can be at any time, and without this a cut placed before it would succeed and
    /// make a first half holding no samples at all.
    public static func split(
        _ sync: SyncSettings, trim: TrimRange, atProjectTime time: Double, fullStart: Double = 0,
        fullDuration: Double?
    ) -> Split? {
        let speed = max(sync.playSpeed, 0.001)
        let fileTime = (time - sync.offsetInProject) * speed + sync.startPositionInInput
        let start = max(max(trim.start ?? fullStart, sync.startPositionInInput), fullStart)
        let end = min(trim.end ?? fullDuration ?? .infinity, fullDuration ?? .infinity)
        // A cut on either edge leaves nothing on one side of it.
        guard fileTime > start + 0.001, fileTime < end - 0.001 else { return nil }

        var second = sync
        second.startPositionInInput = fileTime
        second.offsetInProject = time
        return Split(
            firstEnd: fileTime, secondSync: second,
            secondTrim: TrimRange(start: fileTime, end: trim.end))
    }
}
