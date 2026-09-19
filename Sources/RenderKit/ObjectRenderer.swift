import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Shared state for data-driven display objects: where to draw, and how to get data at a time.
public struct ObjectContext: Sendable {
    public let objectID: DisplayObjectID
    public let frame: UnitRect
    public let opacity: Double
    public let sampler: TelemetrySampler?
    public let sync: SyncSettings
    public let cache: RenderCache

    public init(
        objectID: DisplayObjectID, frame: UnitRect, opacity: Double, sampler: TelemetrySampler?, sync: SyncSettings,
        cache: RenderCache
    ) {
        self.objectID = objectID
        self.frame = frame
        self.opacity = opacity
        self.sampler = sampler
        self.sync = sync
        self.cache = cache
    }

    /// Pixel rectangle of the object for an output of `size`.
    public func rect(in size: CGSize) -> CGRect {
        frame.scaled(toWidth: size.width, height: size.height)
    }

    /// Telemetry at project `time`, mapped through the input's sync settings.
    public func sample(at time: Double) -> TelemetrySample? {
        sampler?.sample(at: sync.inputTime(forProjectTime: time))
    }

    public func inputTime(_ projectTime: Double) -> Double { sync.inputTime(forProjectTime: projectTime) }

    /// Cache key prefix unique to this object at this size.
    public func cacheKey(_ suffix: String, size: CGSize) -> String {
        "\(objectID)|\(Int(size.width))x\(Int(size.height))|\(suffix)"
    }
}

/// Resolves a role identifier and applies display-unit conversion for speed channels.
enum ChannelValue {
    static func role(_ identifier: String) -> ChannelRole? {
        ChannelRole(identifier: identifier)
    }

    /// Speeds and speed differences are stored in m/s and shown in the object's speed unit.
    static func isSpeed(_ identifier: String) -> Bool {
        let role = role(identifier)
        return role == .speed || role == .speedDelta
    }

    /// Value of `identifier` in the sample, converted for display when it is a speed.
    static func display(_ identifier: String, in sample: TelemetrySample?, speedUnit: SpeedDisplayUnit) -> Double? {
        guard let role = role(identifier), let value = sample?[role] else { return nil }
        return isSpeed(identifier) ? value * speedUnit.factorFromMetersPerSecond : value
    }
}
