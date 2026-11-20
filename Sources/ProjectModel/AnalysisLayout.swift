import Foundation
import TelemetryKit

/// The Analysis view's panels (#556), remembered app-wide so the next session opens laid out as
/// the last was: which of delta-T, speed, the map and the friction circle show, the channels
/// traced under speed, and how tall a trace is.
public struct AnalysisLayout: Hashable, Codable, Sendable {
    public var showsDelta: Bool
    public var showsSpeed: Bool
    public var showsMap: Bool
    public var showsFrictionCircle: Bool
    /// The lap's picture, when it has one.
    public var showsPicture: Bool
    /// Traces under speed, top to bottom.
    public var channels: [ChannelRole]
    /// Points.
    public var traceHeight: Double

    public static let standard = AnalysisLayout()
    public static let traceHeights: ClosedRange<Double> = 80...320

    public init(
        showsDelta: Bool = true, showsSpeed: Bool = true, showsMap: Bool = true, showsFrictionCircle: Bool = true,
        showsPicture: Bool = true, channels: [ChannelRole] = [.throttle, .brake], traceHeight: Double = 140
    ) {
        self.showsDelta = showsDelta
        self.showsSpeed = showsSpeed
        self.showsMap = showsMap
        self.showsFrictionCircle = showsFrictionCircle
        self.showsPicture = showsPicture
        self.channels = channels
        self.traceHeight = traceHeight
    }

    /// The layout `text` holds; the standard one for empty or unreadable text.
    public init(preferenceText text: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(text.utf8))) ?? .standard
    }

    public var preferenceText: String {
        (try? JSONEncoder().encode(self)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case showsDelta, showsSpeed, showsMap, showsFrictionCircle, showsPicture, channels, traceHeight
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = AnalysisLayout()
        showsDelta = try c.decodeIfPresent(Bool.self, forKey: .showsDelta) ?? standard.showsDelta
        showsSpeed = try c.decodeIfPresent(Bool.self, forKey: .showsSpeed) ?? standard.showsSpeed
        showsMap = try c.decodeIfPresent(Bool.self, forKey: .showsMap) ?? standard.showsMap
        showsFrictionCircle =
            try c.decodeIfPresent(Bool.self, forKey: .showsFrictionCircle) ?? standard.showsFrictionCircle
        showsPicture = try c.decodeIfPresent(Bool.self, forKey: .showsPicture) ?? standard.showsPicture
        channels = (try? c.decodeIfPresent([ChannelRole].self, forKey: .channels)) ?? standard.channels
        let height = try c.decodeIfPresent(Double.self, forKey: .traceHeight) ?? standard.traceHeight
        traceHeight = min(max(height, Self.traceHeights.lowerBound), Self.traceHeights.upperBound)
    }

    /// Adds a trace for `role` under the others, once.
    public mutating func add(_ role: ChannelRole) {
        guard role != .speed, !channels.contains(role) else { return }
        channels.append(role)
    }

    public mutating func remove(_ role: ChannelRole) { channels.removeAll { $0 == role } }
}
