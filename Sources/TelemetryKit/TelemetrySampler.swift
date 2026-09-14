/// A snapshot of every channel at one moment, plus resolved lap timing.
public struct TelemetrySample: Sendable, Equatable {
    public let time: Double
    public let values: [ChannelRole: Double]
    public let lapTiming: LapTiming

    public subscript(role: ChannelRole) -> Double? { values[role] }
}

/// Samples a session at arbitrary times. Value type; safe to share across threads.
public struct TelemetrySampler: Sendable {
    public let session: TelemetrySession

    public init(session: TelemetrySession) {
        self.session = session
    }

    /// Interpolated value of one role at `time`.
    public func value(of role: ChannelRole, at time: Double) -> Double? {
        session[role]?.value(at: time)
    }

    /// Every channel's value at `time`. Channels without data are omitted.
    public func sample(at time: Double) -> TelemetrySample {
        var values: [ChannelRole: Double] = [:]
        values.reserveCapacity(session.channels.count)
        for (role, channel) in session.channels {
            if let value = channel.value(at: time) { values[role] = value }
        }
        return TelemetrySample(time: time, values: values, lapTiming: LapTiming.resolve(at: time, laps: session.laps))
    }
}
