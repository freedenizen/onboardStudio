import Foundation

/// Resampling and smoothing of channels.
public enum Resampler {
    /// Returns a channel sampled at a uniform `hertz` across its own time range, using the
    /// channel's interpolation policy. Useful to "boost" a low-rate source before smoothing.
    public static func resample(_ channel: Channel, hertz: Double) -> Channel {
        guard hertz > 0, let first = channel.firstTime, let last = channel.lastTime, last > first else {
            return channel
        }
        let step = 1 / hertz
        let count = Int(((last - first) / step).rounded(.down)) + 1
        var times: [Double] = []
        var values: [Double] = []
        times.reserveCapacity(count)
        values.reserveCapacity(count)
        for index in 0..<count {
            let t = first + Double(index) * step
            times.append(t)
            values.append(channel.value(at: t) ?? 0)
        }
        return Channel(
            role: channel.role, name: channel.name, unit: channel.unit, times: times, values: values,
            interpolation: channel.interpolation)
    }

    /// Centred moving average over `windowSeconds`. Step-interpolated channels (gear, lap) are
    /// returned unchanged because averaging discrete values is meaningless.
    public static func smooth(_ channel: Channel, windowSeconds: Double) -> Channel {
        guard windowSeconds > 0, channel.count > 2, channel.interpolation == .linear else { return channel }
        let half = windowSeconds / 2
        var smoothed = [Double](repeating: 0, count: channel.count)
        var lower = 0
        var upper = 0
        var sum = 0.0
        for index in 0..<channel.count {
            let t = channel.times[index]
            while upper < channel.count, channel.times[upper] <= t + half {
                sum += channel.values[upper]
                upper += 1
            }
            while lower < upper, channel.times[lower] < t - half {
                sum -= channel.values[lower]
                lower += 1
            }
            let n = upper - lower
            smoothed[index] = n > 0 ? sum / Double(n) : channel.values[index]
        }
        return Channel(
            role: channel.role, name: channel.name, unit: channel.unit, times: channel.times, values: smoothed,
            interpolation: channel.interpolation)
    }

    /// Circular moving average for headings in degrees (averages unit vectors so 359° and 1° give 0°).
    public static func smoothHeading(_ channel: Channel, windowSeconds: Double) -> Channel {
        guard windowSeconds > 0, channel.count > 2 else { return channel }
        let sinChannel = Channel(
            role: channel.role, name: channel.name, unit: channel.unit, times: channel.times,
            values: channel.values.map { sin($0 * .pi / 180) })
        let cosChannel = Channel(
            role: channel.role, name: channel.name, unit: channel.unit, times: channel.times,
            values: channel.values.map { cos($0 * .pi / 180) })
        let s = smooth(sinChannel, windowSeconds: windowSeconds).values
        let c = smooth(cosChannel, windowSeconds: windowSeconds).values
        let degrees = zip(s, c).map { (atan2($0, $1) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
        return Channel(
            role: channel.role, name: channel.name, unit: channel.unit, times: channel.times, values: degrees,
            interpolation: channel.interpolation)
    }
}
