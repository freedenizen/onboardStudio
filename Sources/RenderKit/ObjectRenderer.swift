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
    /// The speed unit this object actually draws in, already resolved through #75's chain
    /// (object → project → app → the data). Renderers take it from here rather than from their
    /// params, because a params value may still say `automatic`, and `automatic` has no
    /// conversion factor — resolving is `RenderPlanner`'s job and doing it here would scatter it.
    public let speedUnit: SpeedDisplayUnit
    /// The unit every channel of this object's input is drawn in, and what to label it with,
    /// already resolved through #89's chain. Empty means "draw everything as it is stored", which
    /// is what a project with no display units chosen gets.
    public let units: DisplayUnits

    public init(
        objectID: DisplayObjectID, frame: UnitRect, opacity: Double, sampler: TelemetrySampler?, sync: SyncSettings,
        cache: RenderCache, speedUnit: SpeedDisplayUnit = UnitResolver.lastResort,
        units: DisplayUnits? = nil
    ) {
        self.objectID = objectID
        self.frame = frame
        self.opacity = opacity
        self.sampler = sampler
        self.sync = sync
        self.cache = cache
        self.speedUnit = speedUnit
        // Without the fuller chain, speed still converts as #75 made it: a caller that knows only
        // a speed unit gets the drawing it always got, never an empty table quietly drawing m/s.
        self.units = units ?? DisplayUnits(speed: speedUnit)
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

    /// Value of `identifier` in the sample, in the unit it is to be drawn in (#89). Speed is one
    /// case of that rather than the only one: any channel the chain gave a display unit converts
    /// here, from the unit it is stored in.
    static func display(_ identifier: String, in sample: TelemetrySample?, units: DisplayUnits) -> Double? {
        guard let role = role(identifier), let value = sample?[role] else { return nil }
        return units.value(value, of: identifier)
    }
}
