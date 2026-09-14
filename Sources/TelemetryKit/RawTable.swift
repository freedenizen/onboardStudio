import Foundation

/// A parsed column as produced by an importer, before it becomes a `Channel`.
public struct RawColumn: Sendable, Equatable {
    public var name: String
    public var unit: TelemetryUnit
    /// Origin of the column within the file (e.g. RaceChrono's "100: gps", "calc", "200: obd").
    public var source: String?
    /// The importer's best guess for the column's role; `nil` means "unmapped".
    public var suggestedRole: ChannelRole?
    public var interpolation: InterpolationPolicy
    /// Sample values aligned to `RawTable.times`; `nil` where the row had no value.
    public var values: [Double?]

    public init(
        name: String,
        unit: TelemetryUnit = .none,
        source: String? = nil,
        suggestedRole: ChannelRole? = nil,
        interpolation: InterpolationPolicy = .linear,
        values: [Double?] = []
    ) {
        self.name = name
        self.unit = unit
        self.source = source
        self.suggestedRole = suggestedRole
        self.interpolation = interpolation
        self.values = values
    }
}

/// An explicit lap boundary recorded in the file (e.g. RaceRender `# Lap N:` tags).
public struct RawLapMarker: Sendable, Equatable {
    public var number: Int
    public var time: Double

    public init(number: Int, time: Double) {
        self.number = number
        self.time = time
    }
}

/// The importer's output: a time axis, columns, explicit lap markers and metadata.
/// `SessionBuilder` turns it into a `TelemetrySession`.
public struct RawTable: Sendable {
    public var info: SessionInfo
    /// Strictly increasing sample times in seconds (same count as every column's values).
    public var times: [Double]
    public var columns: [RawColumn]
    public var lapMarkers: [RawLapMarker]

    public init(info: SessionInfo, times: [Double], columns: [RawColumn], lapMarkers: [RawLapMarker] = []) {
        self.info = info
        self.times = times
        self.columns = columns
        self.lapMarkers = lapMarkers
    }

    public var rowCount: Int { times.count }

    public func column(named name: String) -> RawColumn? {
        columns.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
