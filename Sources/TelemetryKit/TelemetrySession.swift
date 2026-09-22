import Foundation

/// Descriptive information about where a session came from.
public struct SessionInfo: Sendable, Equatable, Codable {
    public var sourceFormat: String
    public var sourceFileName: String?
    public var title: String?
    public var trackName: String?
    public var driverName: String?
    public var createdAt: Date?
    public var notes: String?

    public init(
        sourceFormat: String,
        sourceFileName: String? = nil,
        title: String? = nil,
        trackName: String? = nil,
        driverName: String? = nil,
        createdAt: Date? = nil,
        notes: String? = nil
    ) {
        self.sourceFormat = sourceFormat
        self.sourceFileName = sourceFileName
        self.title = title
        self.trackName = trackName
        self.driverName = driverName
        self.createdAt = createdAt
        self.notes = notes
    }
}

/// A complete imported data file: channels keyed by role, laps, and source metadata.
public struct TelemetrySession: Sendable {
    public var info: SessionInfo
    public private(set) var channels: [ChannelRole: Channel]
    public var laps: [Lap]
    /// Sector times, measured once when the session was built. `nil` when the file has no laps
    /// or no distance to divide, which is every session recorded without GPS.
    public var sectors: SectorAnalysis?
    /// What the circuit calls its corners, in driving order from the start/finish.
    ///
    /// Strings, not numbers: Sonoma runs 1, 2, 3, **3a**, 4, **4a**, … and letter suffixes are
    /// common. Empty until the driver sets them — no open source publishes corner numbering
    /// (`docs/tracks-and-sectors.md`), so like sector geometry it is drawn, never fetched.
    public var cornerLabels: [String] = []
    /// The unit a channel was *recorded* in, for every role the builder converted to its canonical
    /// unit. `channels[.speed].unit` is always m/s by the time anyone reads it, so this is the
    /// only record of whether the file said mph or kph — which is what *Automatic* in the speed
    /// unit chain means. Kept on the session rather than the channel so that resampling and
    /// smoothing, which rebuild channels, cannot lose it.
    public var recordedUnits: [ChannelRole: TelemetryUnit] = [:]
    /// Every column the file offered, in file order — including the ones no channel was built
    /// from. The session keeps only the columns it could make sense of, so without this there is
    /// no way to offer a user a column the importer ignored, which is exactly the column they
    /// most often need to point an attribute at (#111).
    public var sourceColumns: [String] = []
    /// What became of every column of the file (#149). Kept on the session because the decisions
    /// are made while it is built and cannot be reconstructed from the channels that survived.
    public var importReport = ImportReport()
    /// Start/finish and sector gates the file carried (#71). Empty for the formats that carry
    /// none, which is all of them but Racelogic's VBO.
    public var lapGeometry = LapGeometry()

    public init(info: SessionInfo, channels: [Channel], laps: [Lap] = [], sectors: SectorAnalysis? = nil) {
        self.info = info
        self.channels = Dictionary(channels.map { ($0.role, $0) }, uniquingKeysWith: { first, _ in first })
        self.laps = laps
        self.sectors = sectors
    }

    /// The unit `role` was recorded in: what the file said before canonicalisation, or the
    /// channel's own unit when nothing was converted.
    public func recordedUnit(of role: ChannelRole) -> TelemetryUnit? {
        recordedUnits[role] ?? self[role]?.unit
    }

    /// Falls back to the role's `legacyAlias`, so a project saved when CAN channels were filed
    /// as `obd:` still finds them now that they import as `canbus:`.
    public subscript(role: ChannelRole) -> Channel? {
        if let channel = channels[role] { return channel }
        guard let alias = role.legacyAlias else { return nil }
        return channels[alias]
    }

    public mutating func add(_ channel: Channel) {
        channels[channel.role] = channel
    }

    public mutating func remove(_ role: ChannelRole) {
        channels[role] = nil
    }

    /// Channels ordered: standard roles first (in a fixed order), then vehicle/aux alphabetically.
    public var orderedChannels: [Channel] {
        channels.values.sorted { lhs, rhs in
            let l = Self.sortKey(lhs.role)
            let r = Self.sortKey(rhs.role)
            return l == r ? lhs.name < rhs.name : l < r
        }
    }

    /// Earliest and latest sample time across all channels.
    public var timeRange: ClosedRange<Double>? {
        let starts = channels.values.compactMap(\.firstTime)
        let ends = channels.values.compactMap(\.lastTime)
        guard let start = starts.min(), let end = ends.max(), start.isFinite, end.isFinite, start <= end else {
            return nil
        }
        return start...end
    }

    public var duration: Double { timeRange.map { $0.upperBound - $0.lowerBound } ?? 0 }

    public var hasPosition: Bool { channels[.latitude] != nil && channels[.longitude] != nil }

    private static let standardOrder: [ChannelRole] = [
        .time, .latitude, .longitude, .altitude, .speed, .heading, .distance, .lap,
        .longitudinalG, .lateralG, .rpm, .gear, .throttle, .brake, .lapDelta, .speedDelta, .accuracy, .gpsUpdate,
        .gpsDelay,
    ]

    private static func sortKey(_ role: ChannelRole) -> String {
        if let index = standardOrder.firstIndex(of: role) {
            return String(format: "0%03d", index)
        }
        switch role {
        case .obd(let name): return "1\(name)"
        case .canbus(let name): return "1\(name)"
        case .aux(let name): return "2\(name)"
        default: return "3\(role.identifier)"
        }
    }
}
