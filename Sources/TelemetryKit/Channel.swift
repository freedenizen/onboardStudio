/// How a channel's value is derived between recorded samples.
public enum InterpolationPolicy: String, Sendable, Codable {
    /// Linear interpolation between neighbouring samples (speed, position, RPM).
    case linear
    /// Hold the previous sample until the next one (gear, lap number, flags).
    case step
}

/// A single time-indexed series of values. `times` are strictly increasing seconds and
/// `values` has the same length. Missing samples are simply absent; the sampler interpolates
/// across gaps according to `interpolation`.
public struct Channel: Sendable, Equatable {
    public let role: ChannelRole
    public let name: String
    public let unit: TelemetryUnit
    public let times: [Double]
    public let values: [Double]
    public let interpolation: InterpolationPolicy

    public init(
        role: ChannelRole,
        name: String,
        unit: TelemetryUnit,
        times: [Double],
        values: [Double],
        interpolation: InterpolationPolicy = .linear
    ) {
        precondition(times.count == values.count, "times and values must have equal length")
        self.role = role
        self.name = name
        self.unit = unit
        self.times = times
        self.values = values
        self.interpolation = interpolation
    }

    public var count: Int { times.count }
    public var isEmpty: Bool { times.isEmpty }
    public var minValue: Double? { values.min() }
    public var maxValue: Double? { values.max() }
    public var firstTime: Double? { times.first }
    public var lastTime: Double? { times.last }

    /// Average samples per second over the channel's duration.
    public var sampleRate: Double? {
        guard let first = times.first, let last = times.last, last > first, times.count > 1 else { return nil }
        return Double(times.count - 1) / (last - first)
    }

    /// Value at `time` according to the interpolation policy. Clamps to the first/last sample
    /// outside the recorded range. Returns `nil` for an empty channel.
    public func value(at time: Double) -> Double? {
        guard !times.isEmpty else { return nil }
        if time <= times[0] { return values[0] }
        if time >= times[times.count - 1] { return values[values.count - 1] }
        let upper = times.firstIndex(atOrAfter: time)
        let lower = upper - 1
        if times[upper] == time { return values[upper] }
        switch interpolation {
        case .step:
            return values[lower]
        case .linear:
            let span = times[upper] - times[lower]
            let fraction = span > 0 ? (time - times[lower]) / span : 0
            return values[lower] + (values[upper] - values[lower]) * fraction
        }
    }

    /// Returns a copy with every value multiplied by `factor` and the unit replaced.
    public func scaled(by factor: Double, unit newUnit: TelemetryUnit) -> Channel {
        Channel(
            role: role, name: name, unit: newUnit, times: times, values: values.map { $0 * factor },
            interpolation: interpolation)
    }

    /// Returns a copy converted to the canonical unit for its role when a conversion exists.
    public func convertedToCanonicalUnit() -> Channel {
        guard let target = TelemetryUnit.canonical(for: role), target != unit,
            let factor = unit.conversionFactor(to: target)
        else { return self }
        return scaled(by: factor, unit: target)
    }
}

extension Array where Element == Double {
    /// Index of the first element `>= value` in a sorted array. Returns `count` if none.
    func firstIndex(atOrAfter value: Double) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
