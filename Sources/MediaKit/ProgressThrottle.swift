/// Passes on a long job's progress only when it has moved enough to show (#279).
///
/// Gyroflow prints a line per frame and the exporter reports every frame it writes: tens of
/// thousands of updates for a long video, each one redrawing whatever shows the progress. A bar
/// cannot show a change of less than a pixel or so, so a step of 0.1 % loses nothing a user sees.
public struct ProgressThrottle: Sendable {
    public let step: Double
    private var last: Double?

    public init(step: Double = 0.001) {
        self.step = step
    }

    /// Whether `fraction` should be passed on: the first report, any move of at least `step` either
    /// way, and reaching the end.
    public mutating func shouldReport(_ fraction: Double) -> Bool {
        if let last, abs(fraction - last) < step, !(fraction >= 1 && last < 1) { return false }
        last = fraction
        return true
    }
}
