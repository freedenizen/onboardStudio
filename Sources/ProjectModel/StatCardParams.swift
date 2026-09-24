import Foundation

/// What a stat card counts over (#151).
public enum StatCardScope: String, Codable, Sendable, CaseIterable {
    /// The whole session: best lap, top speed, optimal lap, laps completed.
    case session
    /// The lap at the playhead: its time, how it compares with the best, its top speed — what a
    /// clip of one lap wants to say.
    case lapAtPlayhead
}

/// The headline numbers of a session on one card, for a shareable clip (#151).
public struct StatCardParams: Hashable, Codable, Sendable {
    /// The line at the top. Project details fill in by name, as in a Text object: `{track} · {date}`.
    public var title: String
    public var scope: StatCardScope
    public var showBestLap: Bool
    public var showTopSpeed: Bool
    public var showOptimalLap: Bool
    public var showLapCount: Bool
    public var speedUnit: SpeedUnitSetting
    public var textColor: RGBAColor
    public var labelColor: RGBAColor
    public var backgroundColor: RGBAColor

    public init(
        title: String = "{track} · {date}",
        scope: StatCardScope = .session,
        showBestLap: Bool = true,
        showTopSpeed: Bool = true,
        showOptimalLap: Bool = true,
        showLapCount: Bool = true,
        speedUnit: SpeedUnitSetting = .automatic,
        textColor: RGBAColor = .white,
        labelColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.7),
        backgroundColor: RGBAColor = .translucentBlack
    ) {
        self.title = title
        self.scope = scope
        self.showBestLap = showBestLap
        self.showTopSpeed = showTopSpeed
        self.showOptimalLap = showOptimalLap
        self.showLapCount = showLapCount
        self.speedUnit = speedUnit
        self.textColor = textColor
        self.labelColor = labelColor
        self.backgroundColor = backgroundColor
    }

    private enum CodingKeys: String, CodingKey {
        case title, scope, showBestLap, showTopSpeed, showOptimalLap, showLapCount, speedUnit
        case textColor, labelColor, backgroundColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StatCardParams()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? d.title
        scope = try c.decodeIfPresent(StatCardScope.self, forKey: .scope) ?? d.scope
        showBestLap = try c.decodeIfPresent(Bool.self, forKey: .showBestLap) ?? d.showBestLap
        showTopSpeed = try c.decodeIfPresent(Bool.self, forKey: .showTopSpeed) ?? d.showTopSpeed
        showOptimalLap = try c.decodeIfPresent(Bool.self, forKey: .showOptimalLap) ?? d.showOptimalLap
        showLapCount = try c.decodeIfPresent(Bool.self, forKey: .showLapCount) ?? d.showLapCount
        speedUnit = try c.decodeIfPresent(SpeedUnitSetting.self, forKey: .speedUnit) ?? d.speedUnit
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        labelColor = try c.decodeIfPresent(RGBAColor.self, forKey: .labelColor) ?? d.labelColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
    }
}
