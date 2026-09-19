import Foundation

/// A translucent steering-wheel rim with a top-centre marker that turns with the steering angle,
/// as track-day apps draw it over the bottom of the picture. Place it so that only the upper arc
/// is inside the frame (objects may extend past the edges).
public struct SteeringWheelParams: Hashable, Codable, Sendable {
    /// The steering-angle channel. Empty until bound; loggers name it differently.
    public var channel: String
    /// Degrees of wheel rotation per channel unit (1 for degrees, 57.3 for radians, the lock angle
    /// for a −1…1 channel).
    public var degreesPerUnit: Double
    /// Loggers disagree on the sign of a right turn.
    public var invert: Bool
    /// Clamp of the drawn rotation in degrees either way (0 = none).
    public var maxDegrees: Double
    public var rimColor: RGBAColor
    /// A thin line along both edges of the rim so a dark, see-through rim still reads over a
    /// dark cockpit (clear = none).
    public var edgeColor: RGBAColor
    /// Rim thickness as a fraction of the wheel radius.
    public var rimWidth: Double
    public var markerColor: RGBAColor
    /// Marker width as a fraction of the wheel radius.
    public var markerWidth: Double
    /// Three spokes and a hub, turning with the wheel.
    public var showSpokes: Bool
    public var spokeColor: RGBAColor

    public init(
        channel: String = "", degreesPerUnit: Double = 1, invert: Bool = false, maxDegrees: Double = 0,
        rimColor: RGBAColor = RGBAColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 0.55),
        edgeColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.28), rimWidth: Double = 0.16,
        markerColor: RGBAColor = RGBAColor(red: 1, green: 0.84, blue: 0.1), markerWidth: Double = 0.045,
        showSpokes: Bool = false, spokeColor: RGBAColor = RGBAColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 0.4)
    ) {
        self.channel = channel
        self.degreesPerUnit = degreesPerUnit
        self.invert = invert
        self.maxDegrees = maxDegrees
        self.rimColor = rimColor
        self.edgeColor = edgeColor
        self.rimWidth = rimWidth
        self.markerColor = markerColor
        self.markerWidth = markerWidth
        self.showSpokes = showSpokes
        self.spokeColor = spokeColor
    }

    private enum CodingKeys: String, CodingKey {
        case channel, degreesPerUnit, invert, maxDegrees, rimColor, rimWidth, markerColor, markerWidth, showSpokes
        case spokeColor, edgeColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SteeringWheelParams()
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? d.channel
        degreesPerUnit = try c.decodeIfPresent(Double.self, forKey: .degreesPerUnit) ?? d.degreesPerUnit
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? d.invert
        maxDegrees = try c.decodeIfPresent(Double.self, forKey: .maxDegrees) ?? d.maxDegrees
        rimColor = try c.decodeIfPresent(RGBAColor.self, forKey: .rimColor) ?? d.rimColor
        edgeColor = try c.decodeIfPresent(RGBAColor.self, forKey: .edgeColor) ?? d.edgeColor
        rimWidth = try c.decodeIfPresent(Double.self, forKey: .rimWidth) ?? d.rimWidth
        markerColor = try c.decodeIfPresent(RGBAColor.self, forKey: .markerColor) ?? d.markerColor
        markerWidth = try c.decodeIfPresent(Double.self, forKey: .markerWidth) ?? d.markerWidth
        showSpokes = try c.decodeIfPresent(Bool.self, forKey: .showSpokes) ?? d.showSpokes
        spokeColor = try c.decodeIfPresent(RGBAColor.self, forKey: .spokeColor) ?? d.spokeColor
    }

    /// The rotation drawn for a channel value, in degrees clockwise.
    public func rotation(for value: Double) -> Double {
        guard value.isFinite else { return 0 }
        var degrees = value * degreesPerUnit * (invert ? -1 : 1)
        if maxDegrees > 0 { degrees = min(max(degrees, -maxDegrees), maxDegrees) }
        return degrees
    }

    /// The channel that most likely carries the steering angle in this input.
    public func suggestedChannel(among channels: [ChannelSummary]) -> String? {
        func tokens(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        return channels.first { channel in
            let parts = tokens(channel.identifier) + tokens(channel.name)
            return parts.contains { $0.hasPrefix("steer") || $0 == "swa" }
        }?.identifier
    }

    /// Bound to the input's steering channel when it has one; the scale follows the values it
    /// takes (a few units = radians, within ±1 = a normalised channel shown over ±450°).
    public func adapted(to channels: [ChannelSummary]) -> SteeringWheelParams {
        var result = self
        if !channel.isEmpty, channels.contains(where: { $0.identifier == channel }) { return result }
        guard let pick = suggestedChannel(among: channels) else { return result }
        result.channel = pick
        if let summary = channels.first(where: { $0.identifier == pick }), let low = summary.minValue,
            let high = summary.maxValue
        {
            let extent = max(abs(low), abs(high))
            if extent > 0, extent <= 1.05 {
                result.degreesPerUnit = 450
            } else if extent <= 12 {
                result.degreesPerUnit = 180 / Double.pi
            }
        }
        return result
    }
}
