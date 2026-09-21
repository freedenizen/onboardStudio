/// Maps project time to an input file's own time. Used identically for video tracks and telemetry:
/// `inputTime = (projectTime − offsetInProject) × playSpeed + startPositionInInput`.
public struct SyncSettings: Hashable, Codable, Sendable {
    /// Seconds into the input file that correspond to `offsetInProject` on the project timeline.
    public var startPositionInInput: Double
    /// Project time (seconds) at which this input begins playing.
    public var offsetInProject: Double
    /// Playback rate: 1 = normal, 2 = double speed, 0.5 = half speed.
    public var playSpeed: Double

    public init(startPositionInInput: Double = 0, offsetInProject: Double = 0, playSpeed: Double = 1) {
        self.startPositionInInput = startPositionInInput
        self.offsetInProject = offsetInProject
        self.playSpeed = playSpeed
    }

    public static let identity = SyncSettings()

    public func inputTime(forProjectTime projectTime: Double) -> Double {
        (projectTime - offsetInProject) * playSpeed + startPositionInInput
    }

    public func projectTime(forInputTime inputTime: Double) -> Double {
        (inputTime - startPositionInInput) / playSpeed + offsetInProject
    }

    // MARK: - Falling off the front

    /// Where this input begins on the project timeline, which is never before the project does.
    ///
    /// A negative `offsetInProject` means the head of the input sits before the project starts.
    /// The timeline does not stretch backwards to meet it — nothing can be placed before zero, and
    /// AVFoundation fails the entire composition if asked to — so that part is simply not used.
    ///
    /// **The offset itself keeps the value it was given.** Nudging the sync one way and back again
    /// has to put back exactly what it took, and clamping the stored value would quietly make the
    /// first nudge unrepeatable.
    public var startInProject: Double { max(0, offsetInProject) }

    /// Seconds of the *input file* that fall before the project begins, and so are not used.
    ///
    /// In input seconds rather than project seconds: at double speed a tenth of a second off the
    /// front of the timeline is two tenths of the file.
    public var inputSecondsBeforeProjectStart: Double { max(0, -offsetInProject) * playSpeed }
}

/// Optional start/end trim of an input in the input's own time.
public struct TrimRange: Hashable, Codable, Sendable {
    public var start: Double?
    public var end: Double?

    public init(start: Double? = nil, end: Double? = nil) {
        self.start = start
        self.end = end
    }

    public static let none = TrimRange()
}
