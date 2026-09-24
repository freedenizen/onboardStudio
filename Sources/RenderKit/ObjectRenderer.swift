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
    /// The font this object's text is drawn in, already resolved object → project (#118); `nil`
    /// keeps the fonts each renderer draws in by itself.
    public let typeface: Typeface?
    /// How much larger than it lays it out this object draws its text (#118).
    public let textScale: Double
    /// The project's lap comparison, when it has one (#154): every object can measure against the
    /// compared lap, and one that follows it reads its data through the warp.
    public let lapComparison: LapTimeWarp?
    /// Reads the compared lap's data, at the same point round the lap, instead of the lap playing.
    public let followsComparedLap: Bool

    public init(
        objectID: DisplayObjectID, frame: UnitRect, opacity: Double, sampler: TelemetrySampler?, sync: SyncSettings,
        cache: RenderCache, speedUnit: SpeedDisplayUnit = UnitResolver.lastResort,
        units: DisplayUnits? = nil, typeface: Typeface? = nil, textScale: Double = 1,
        lapComparison: LapTimeWarp? = nil, followsComparedLap: Bool = false
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
        self.typeface = typeface
        self.textScale = textScale
        self.lapComparison = lapComparison
        self.followsComparedLap = followsComparedLap && lapComparison != nil
    }

    /// `style` in this object's chosen font and text size. Every renderer passes its text styles
    /// through here, so a choice reaches all of an object's text and not just the part that
    /// happened to have a font field.
    public func styled(_ style: TextDrawing.Style) -> TextDrawing.Style {
        var style = style
        style.typeface = typeface
        style.pointSize *= textScale
        return style
    }

    /// Pixel rectangle of the object for an output of `size`.
    public func rect(in size: CGSize) -> CGRect {
        frame.scaled(toWidth: size.width, height: size.height)
    }

    /// Telemetry at project `time`, mapped through the input's sync settings.
    public func sample(at time: Double) -> TelemetrySample? {
        sampler?.sample(at: inputTime(time))
    }

    /// The time in this object's data file for project `projectTime` — the compared lap's moment
    /// at the same point round the lap, for an object that follows it.
    public func inputTime(_ projectTime: Double) -> Double {
        let time = followsComparedLap ? (lapComparison?.comparedTime(at: projectTime) ?? projectTime) : projectTime
        return sync.inputTime(forProjectTime: time)
    }

    /// Seconds behind (+) or ahead of (−) the other lap of the comparison at the same point round
    /// the lap, seen from the lap this object shows; `nil` without a comparison or outside the lap.
    public func deltaToComparedLap(at projectTime: Double) -> Double? {
        guard let delta = lapComparison?.delta(at: projectTime) else { return nil }
        return followsComparedLap ? -delta : delta
    }

    /// Cache key prefix unique to this object at this size.
    /// The font is part of it: a cached gauge face has its labels drawn into it.
    public func cacheKey(_ suffix: String, size: CGSize) -> String {
        "\(objectID)|\(Int(size.width))x\(Int(size.height))|\(typeface?.displayName ?? "")|\(textScale)|\(suffix)"
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
