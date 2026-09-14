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
