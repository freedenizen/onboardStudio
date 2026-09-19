import Foundation

/// Turns a `RawTable` into a `TelemetrySession`: drops unmapped columns, converts units to
/// canonical ones, removes empty samples, and derives laps from markers or a lap-number column.
public enum SessionBuilder {
    public struct Options: Sendable {
        /// Override or supply roles per column name (case-insensitive). Wins over `suggestedRole`.
        public var roleOverrides: [String: ChannelRole]
        /// Whether to derive a speed channel from position when the file has none.
        public var deriveSpeedFromPosition: Bool
        /// Whether to derive heading from position when the file has none.
        public var deriveHeadingFromPosition: Bool
        /// Whether to derive distance travelled from position when the file has none.
        public var deriveDistanceFromPosition: Bool
        /// Column name → unit override (e.g. a bare "Speed" column that is really km/h).
        public var unitOverrides: [String: TelemetryUnit]
        /// Resample every linear channel to this rate before smoothing (`nil` = keep as recorded).
        public var resampleHertz: Double?
        /// Centred moving-average window applied to linear channels (0 = none).
        public var smoothingSeconds: Double
        /// Additional channels computed from expressions.
        public var calculatedFields: [CalculatedField]
        /// Lap detection from a finish line; `nil` keeps the file's own laps.
        public var finishLine: FinishLine?
        public var ignoreFirstCrossings: Int

        public init(
            roleOverrides: [String: ChannelRole] = [:],
            deriveSpeedFromPosition: Bool = true,
            deriveHeadingFromPosition: Bool = true,
            deriveDistanceFromPosition: Bool = true,
            unitOverrides: [String: TelemetryUnit] = [:],
            resampleHertz: Double? = nil,
            smoothingSeconds: Double = 0,
            calculatedFields: [CalculatedField] = [],
            finishLine: FinishLine? = nil,
            ignoreFirstCrossings: Int = 0
        ) {
            self.roleOverrides = roleOverrides
            self.deriveSpeedFromPosition = deriveSpeedFromPosition
            self.deriveHeadingFromPosition = deriveHeadingFromPosition
            self.deriveDistanceFromPosition = deriveDistanceFromPosition
            self.unitOverrides = unitOverrides
            self.resampleHertz = resampleHertz
            self.smoothingSeconds = smoothingSeconds
            self.calculatedFields = calculatedFields
            self.finishLine = finishLine
            self.ignoreFirstCrossings = ignoreFirstCrossings
        }
    }

    public static func build(_ rawTable: RawTable, options: Options = Options()) -> TelemetrySession {
        let table = sanitised(rawTable)
        var channels: [Channel] = []
        var usedRoles = Set<ChannelRole>()

        for column in table.columns {
            let override = options.roleOverrides.first {
                $0.key.caseInsensitiveCompare(column.name) == .orderedSame
            }?.value
            guard let role = override ?? column.suggestedRole else { continue }
            // First column wins for a given role; later duplicates become aux channels.
            let finalRole: ChannelRole
            if usedRoles.contains(role) {
                let suffix = column.source.map { " (\($0))" } ?? ""
                finalRole = .aux(column.name + suffix)
            } else {
                finalRole = role
            }
            usedRoles.insert(finalRole)
            var effectiveColumn = column
            if let unit = options.unitOverrides.first(where: {
                $0.key.caseInsensitiveCompare(column.name) == .orderedSame
            })?.value {
                effectiveColumn.unit = unit
            }
            guard var channel = makeChannel(role: finalRole, column: effectiveColumn, times: table.times) else {
                continue
            }
            channel = channel.convertedToCanonicalUnit()
            if let hertz = options.resampleHertz, channel.interpolation == .linear {
                channel = Resampler.resample(channel, hertz: hertz)
            }
            if options.smoothingSeconds > 0 {
                channel =
                    channel.role == .heading
                    ? Resampler.smoothHeading(channel, windowSeconds: options.smoothingSeconds)
                    : Resampler.smooth(channel, windowSeconds: options.smoothingSeconds)
            }
            channels.append(channel)
        }

        var session = TelemetrySession(info: table.info, channels: channels)
        addDerivedChannels(to: &session, options: options)
        for field in options.calculatedFields {
            try? session.addCalculatedField(field)
        }
        if let line = options.finishLine {
            session.laps = LapDetector.detect(in: session, line: line, ignoreFirst: options.ignoreFirstCrossings)
        } else {
            session.laps = deriveLaps(table: table, session: session)
        }
        // Pit-lane fragments cannot be the best lap, and every object can read the deltas to it.
        session.laps = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
        for channel in LapDeltas.channels(for: session) { session.add(channel) }
        return session
    }

    // MARK: - Time axis

    /// Every importer promises a finite, strictly increasing time axis, but a corrupt file can
    /// break that promise; rows with NaN, infinite or non-increasing times are dropped here so
    /// binary searches and time ranges stay valid.
    static func sanitised(_ table: RawTable) -> RawTable {
        var keep: [Int] = []
        keep.reserveCapacity(table.times.count)
        var last = -Double.infinity
        for (index, time) in table.times.enumerated() where time.isFinite && time > last {
            keep.append(index)
            last = time
        }
        guard keep.count != table.times.count else { return table }
        var out = table
        out.times = keep.map { table.times[$0] }
        out.columns = table.columns.map { column in
            var copy = column
            copy.values = keep.map { $0 < column.values.count ? column.values[$0] : nil }
            return copy
        }
        return out
    }

    // MARK: - Channels

    private static func makeChannel(role: ChannelRole, column: RawColumn, times: [Double]) -> Channel? {
        var t: [Double] = []
        var v: [Double] = []
        t.reserveCapacity(times.count)
        v.reserveCapacity(times.count)
        for (index, value) in column.values.enumerated() where index < times.count {
            guard let value, value.isFinite else { continue }
            t.append(times[index])
            v.append(value)
        }
        guard !t.isEmpty else { return nil }
        let interpolation: InterpolationPolicy =
            switch role {
            case .lap, .gear, .gpsUpdate: .step
            default: column.interpolation
            }
        return Channel(
            role: role, name: column.name, unit: column.unit, times: t, values: v, interpolation: interpolation)
    }

    private static func addDerivedChannels(to session: inout TelemetrySession, options: Options) {
        guard let lat = session[.latitude], let lon = session[.longitude] else { return }
        if options.deriveSpeedFromPosition, session[.speed] == nil,
            let speed = DerivedChannels.speed(latitude: lat, longitude: lon)
        {
            session.add(speed)
        }
        if options.deriveHeadingFromPosition, session[.heading] == nil,
            let heading = DerivedChannels.heading(latitude: lat, longitude: lon)
        {
            session.add(heading)
        }
        if options.deriveDistanceFromPosition, session[.distance] == nil,
            let distance = DerivedChannels.distance(latitude: lat, longitude: lon)
        {
            session.add(distance)
        }
    }

    // MARK: - Laps

    /// Explicit markers take precedence; otherwise laps come from transitions of a lap-number
    /// channel. Returns an empty array if neither is available.
    static func deriveLaps(table: RawTable, session: TelemetrySession) -> [Lap] {
        let end = session.timeRange?.upperBound
        if !table.lapMarkers.isEmpty {
            return lapsFromMarkers(table.lapMarkers.sorted { $0.time < $1.time }, sessionEnd: end)
        }
        if let lapChannel = session[.lap] {
            return lapsFromLapNumbers(lapChannel, sessionEnd: end)
        }
        return []
    }

    /// RaceRender semantics: `# Lap N: t` marks the *end* of lap N at time t. Lap 0 starts at
    /// the session start; each subsequent lap starts where the previous ended.
    private static func lapsFromMarkers(_ markers: [RawLapMarker], sessionEnd: Double?) -> [Lap] {
        var laps: [Lap] = []
        var start = 0.0
        for marker in markers {
            laps.append(Lap(number: marker.number, start: start, end: marker.time, isComplete: true))
            start = marker.time
        }
        if let sessionEnd, sessionEnd > start, let lastNumber = markers.last?.number {
            laps.append(Lap(number: lastNumber + 1, start: start, end: sessionEnd, isComplete: false))
        }
        return laps
    }

    /// Contiguous runs of the same lap number become laps. The first run is marked incomplete
    /// when the data starts mid-lap (its number is not 0) and the last run is incomplete because
    /// the file ends before the next boundary.
    private static func lapsFromLapNumbers(_ channel: Channel, sessionEnd: Double?) -> [Lap] {
        guard !channel.isEmpty else { return [] }
        // Lap numbers are small integers; anything else (a corrupt file) is clamped, not trapped on.
        func lapNumber(_ value: Double) -> Int { Int(min(max(value.isFinite ? value.rounded() : 0, -1e6), 1e6)) }
        var runs: [(number: Int, start: Double)] = []
        var current = lapNumber(channel.values[0])
        runs.append((current, channel.times[0]))
        for index in 1..<channel.count {
            let number = lapNumber(channel.values[index])
            if number != current {
                current = number
                runs.append((number, channel.times[index]))
            }
        }
        var laps: [Lap] = []
        for (index, run) in runs.enumerated() {
            let isLast = index == runs.count - 1
            let end = isLast ? sessionEnd : runs[index + 1].start
            let isFirstPartial = index == 0 && run.number != 0
            laps.append(Lap(number: run.number, start: run.start, end: end, isComplete: !isLast && !isFirstPartial))
        }
        return laps
    }
}
