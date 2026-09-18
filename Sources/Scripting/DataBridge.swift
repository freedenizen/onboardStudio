import Foundation
import JavaScriptCore
import ProjectModel
import RenderKit
import TelemetryKit

/// The telemetry API a script sees as `data`.
@objc protocol DataExports: JSExport {
    /// Project time in seconds.
    var time: Double { get }
    /// Time inside the data file in seconds.
    var inputTime: Double { get }
    /// Channel identifiers available in the session.
    var channels: [String] { get }
    /// Lap timing: `{ number, elapsed, last, best, bestNumber, delta }` (nulls when unknown).
    var lap: [String: Any] { get }
    /// Every lap in the session: `[{ number, start, duration }]`.
    var laps: [[String: Any]] { get }
    /// Session length in seconds.
    var duration: Double { get }
    func has(_ channel: String) -> Bool
    /// The channel's value in its canonical unit (speed in m/s, distances in m, angles in degrees), or null.
    func value(_ channel: String) -> Any?
    /// Speed in "mph", "kph" or "ms", or null.
    func speed(_ unit: String) -> Any?
    /// The channel's value `secondsAgo` seconds earlier, or null.
    func valueAgo(_ channel: String, _ secondsAgo: Double) -> Any?
    /// Minimum and maximum of a channel over the whole session: `[min, max]` or null.
    func range(_ channel: String) -> Any?
}

/// Answers data queries for the frame being drawn.
final class DataBridge: NSObject, DataExports {
    var context: ObjectContext?
    var time: Double = 0
    private var sample: TelemetrySample?

    func begin(context: ObjectContext, time: Double) {
        self.context = context
        self.time = time
        sample = context.sample(at: time)
    }

    var inputTime: Double { context?.inputTime(time) ?? time }

    var channels: [String] {
        context?.sampler?.session.orderedChannels.map(\.role.identifier) ?? []
    }

    var duration: Double { context?.sampler?.session.duration ?? 0 }

    var lap: [String: Any] {
        guard let timing = sample?.lapTiming else { return [:] }
        var result: [String: Any] = [:]
        result["number"] = timing.currentLap?.number ?? NSNull()
        result["elapsed"] = timing.elapsedInLap ?? NSNull()
        result["last"] = timing.lastLapTime ?? NSNull()
        result["best"] = timing.bestLapTime ?? NSNull()
        result["bestNumber"] = timing.bestLapNumber ?? NSNull()
        if let session = context?.sampler?.session, let sample,
            let delta = LapComparison.deltaToBest(at: sample.time, session: session)
        {
            result["delta"] = delta
        } else {
            result["delta"] = NSNull()
        }
        return result
    }

    var laps: [[String: Any]] {
        (context?.sampler?.session.laps ?? []).map { lap in
            ["number": lap.number, "start": lap.start, "duration": lap.duration ?? NSNull()]
        }
    }

    func has(_ channel: String) -> Bool {
        guard let role = ChannelRole(identifier: channel) else { return false }
        return context?.sampler?.session[role] != nil
    }

    func value(_ channel: String) -> Any? {
        guard let role = ChannelRole(identifier: channel), let value = sample?[role] else { return NSNull() }
        return value
    }

    func speed(_ unit: String) -> Any? {
        guard let value = sample?[.speed] else { return NSNull() }
        switch unit.lowercased() {
        case "mph": return value * SpeedDisplayUnit.mph.factorFromMetersPerSecond
        case "kph", "km/h", "kmh": return value * SpeedDisplayUnit.kph.factorFromMetersPerSecond
        default: return value
        }
    }

    func valueAgo(_ channel: String, _ secondsAgo: Double) -> Any? {
        guard let role = ChannelRole(identifier: channel), let context,
            let value = context.sampler?.value(of: role, at: context.inputTime(time - secondsAgo))
        else { return NSNull() }
        return value
    }

    func range(_ channel: String) -> Any? {
        guard let role = ChannelRole(identifier: channel), let ch = context?.sampler?.session[role],
            let low = ch.minValue, let high = ch.maxValue
        else { return NSNull() }
        return [low, high]
    }
}
