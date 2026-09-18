import Foundation

/// Finds the time offset between two uniformly sampled signals by normalised cross-correlation.
/// Used to line a data log up with a video from what they both record: the car moving.
public enum SignalCorrelation {
    public struct Result: Sendable, Equatable {
        /// Seconds to add to a time on the short signal's axis to reach the same instant on the
        /// long signal's axis.
        public let offset: Double
        /// Pearson correlation at the best offset, −1…1.
        public let score: Double
        /// How much the best peak stands out from the next best one away from it, 0…1.
        public let prominence: Double

        public init(offset: Double, score: Double, prominence: Double) {
            self.offset = offset
            self.score = score
            self.prominence = prominence
        }
    }

    /// Resamples an irregular series to `rate` Hz with linear interpolation, starting at the
    /// first sample. Returns the series and its start time.
    public static func resample(times: [Double], values: [Double], rate: Double) -> (start: Double, values: [Double]) {
        guard let first = times.first, let last = times.last, last > first, rate > 0 else { return (0, []) }
        let count = Int(((last - first) * rate).rounded(.down)) + 1
        var out = [Double](repeating: 0, count: count)
        var cursor = 0
        for index in 0..<count {
            let t = first + Double(index) / rate
            while cursor + 1 < times.count, times[cursor + 1] < t { cursor += 1 }
            if cursor + 1 < times.count {
                let span = times[cursor + 1] - times[cursor]
                let f = span > 0 ? (t - times[cursor]) / span : 0
                out[index] = values[cursor] + (values[cursor + 1] - values[cursor]) * min(max(f, 0), 1)
            } else {
                out[index] = values[cursor]
            }
        }
        return (first, out)
    }

    /// Removes slow drift (moving average over `window` samples) and scales to unit variance.
    /// A `window` of 0 removes the plain mean instead of a moving average.
    public static func normalise(_ values: [Double], window: Int) -> [Double] {
        guard values.count > 1 else { return values.map { _ in 0 } }
        let half = window > 0 ? max(1, window / 2) : values.count
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for (index, value) in values.enumerated() { prefix[index + 1] = prefix[index] + value }
        var detrended = [Double](repeating: 0, count: values.count)
        for index in 0..<values.count {
            let lo = max(0, index - half)
            let hi = min(values.count, index + half + 1)
            let mean = (prefix[hi] - prefix[lo]) / Double(hi - lo)
            detrended[index] = values[index] - mean
        }
        let variance = detrended.reduce(0) { $0 + $1 * $1 } / Double(values.count)
        guard variance > 1e-12 else { return detrended.map { _ in 0 } }
        let scale = 1 / variance.squareRoot()
        return detrended.map { $0 * scale }
    }

    /// Slides `short` along `long` (both at `rate` Hz, both starting at time 0 of their own axes)
    /// and returns the offset with the highest Pearson correlation. At least `minimumOverlap`
    /// (fraction of `short`) must overlap. `nil` when either signal is flat or too short.
    public static func bestOffset(
        short: [Double], long: [Double], rate: Double, minimumOverlap: Double = 0.7, rivalDistance: Double = 20
    ) -> Result? {
        let a = short
        let b = long
        guard a.count >= 8, b.count >= 8, rate > 0 else { return nil }
        let minOverlap = max(8, Int(Double(a.count) * minimumOverlap))
        // Lag k means a[i] lines up with b[i + k].
        let first = -(a.count - minOverlap)
        let last = b.count - minOverlap
        guard last >= first else { return nil }
        var scores: [(lag: Int, score: Double)] = []
        scores.reserveCapacity(last - first + 1)
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for lag in first...last {
                    let start = max(0, -lag)
                    let end = min(a.count, b.count - lag)
                    let n = end - start
                    guard n >= minOverlap else { continue }
                    var sa = 0.0
                    var sb = 0.0
                    var saa = 0.0
                    var sbb = 0.0
                    var sab = 0.0
                    for i in start..<end {
                        let x = pa[i]
                        let y = pb[i + lag]
                        sa += x
                        sb += y
                        saa += x * x
                        sbb += y * y
                        sab += x * y
                    }
                    let count = Double(n)
                    let cov = sab - sa * sb / count
                    let va = saa - sa * sa / count
                    let vb = sbb - sb * sb / count
                    guard va > 1e-9, vb > 1e-9 else { continue }
                    scores.append((lag, cov / (va * vb).squareRoot()))
                }
            }
        }
        guard let best = scores.max(by: { $0.score < $1.score }), best.score > 0 else { return nil }
        // The runner-up must be well away from the peak (a correlation peak is tens of seconds
        // wide when the signals are speed-like) to count as a rival alignment.
        let exclusion = Int(rivalDistance * rate)
        let rival = scores.filter { abs($0.lag - best.lag) > exclusion }.map(\.score).max() ?? 0
        let prominence = best.score > 0 ? min(max((best.score - max(rival, 0)) / best.score, 0), 1) : 0
        return Result(offset: Double(best.lag) / rate, score: best.score, prominence: prominence)
    }
}
