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
        /// Attribute → the column that supplies it (#111): the reverse of `roleOverrides`, and the
        /// direction the user asks in — "Brake comes from canbus:front_brake_pressure" rather than
        /// "what is this column?". An attribute named here keeps its column even when an earlier
        /// column in the file would have been guessed into the same role.
        public var sourceColumns: [ChannelRole: String]
        /// Attribute → the unit its numbers are to be *read* in (#111), whatever the file declared.
        /// Attribute-keyed rather than column-keyed so that a unit can be corrected without also
        /// having to name the column, which is the common case: the column was matched correctly
        /// and only its unit is missing or wrong.
        public var sourceUnits: [ChannelRole: TelemetryUnit]
        /// Resample every linear channel to this rate before smoothing (`nil` = keep as recorded).
        public var resampleHertz: Double?
        /// Centred moving-average window applied to linear channels (0 = none).
        public var smoothingSeconds: Double
        /// Additional channels computed from expressions.
        public var calculatedFields: [CalculatedField]
        /// Lap detection from a finish line; `nil` keeps the file's own laps.
        public var finishLine: FinishLine?
        public var ignoreFirstCrossings: Int
        /// How laps are split into sectors. Three equal parts is the convention and costs a
        /// binary search per boundary per lap, so it is always measured rather than asked for.
        public var sectorMode: SectorMode
        /// What the circuit calls its corners, in driving order. Empty leaves them unnamed.
        public var cornerLabels: [String]
        /// Ignore samples before this point in the file's own time (`nil` = from the beginning).
        ///
        /// Applied before anything else, so the session behaves as if the recording had started
        /// there: laps are detected, deltas computed and channels derived from what is left. A
        /// trimmed-away out-lap does not become lap 1 and does not compete for the best lap.
        public var trimStart: Double?
        /// Ignore samples after this point (`nil` = to the end).
        public var trimEnd: Double?

        public init(
            roleOverrides: [String: ChannelRole] = [:],
            deriveSpeedFromPosition: Bool = true,
            deriveHeadingFromPosition: Bool = true,
            deriveDistanceFromPosition: Bool = true,
            unitOverrides: [String: TelemetryUnit] = [:],
            sourceColumns: [ChannelRole: String] = [:],
            sourceUnits: [ChannelRole: TelemetryUnit] = [:],
            resampleHertz: Double? = nil,
            smoothingSeconds: Double = 0,
            calculatedFields: [CalculatedField] = [],
            finishLine: FinishLine? = nil,
            ignoreFirstCrossings: Int = 0,
            sectorMode: SectorMode = .equalDistance(count: SectorMode.defaultCount),
            cornerLabels: [String] = [],
            trimStart: Double? = nil,
            trimEnd: Double? = nil
        ) {
            self.trimStart = trimStart
            self.trimEnd = trimEnd
            self.roleOverrides = roleOverrides
            self.deriveSpeedFromPosition = deriveSpeedFromPosition
            self.deriveHeadingFromPosition = deriveHeadingFromPosition
            self.deriveDistanceFromPosition = deriveDistanceFromPosition
            self.unitOverrides = unitOverrides
            self.sourceColumns = sourceColumns
            self.sourceUnits = sourceUnits
            self.resampleHertz = resampleHertz
            self.smoothingSeconds = smoothingSeconds
            self.calculatedFields = calculatedFields
            self.finishLine = finishLine
            self.ignoreFirstCrossings = ignoreFirstCrossings
            self.sectorMode = sectorMode
            self.cornerLabels = cornerLabels
        }
    }

    public static func build(_ rawTable: RawTable, options: Options = Options()) -> TelemetrySession {
        let table = trimmed(sanitised(rawTable), from: options.trimStart, to: options.trimEnd)
        var channels: [Channel] = []
        var recordedUnits: [ChannelRole: TelemetryUnit] = [:]
        var mapper = ColumnMapper(options: options)

        var report = ImportReport()

        for (index, column) in table.columns.enumerated() {
            guard let mapping = mapper.map(column) else {
                report.columns.append(ColumnMapper.reportedColumn(index, column, mapping: nil, mapper: mapper))
                continue
            }
            let (finalRole, effectiveColumn) = (mapping.role, mapping.column)
            guard var channel = makeChannel(role: finalRole, column: effectiveColumn, times: table.times) else {
                report.columns.append(ColumnMapper.reportedColumn(index, effectiveColumn, mapping: nil, mapper: mapper))
                continue
            }
            report.columns.append(ColumnMapper.reportedColumn(index, effectiveColumn, mapping: mapping, mapper: mapper))
            let recordedUnit = channel.unit
            channel = channel.convertedToCanonicalUnit()
            if channel.unit != recordedUnit { recordedUnits[finalRole] = recordedUnit }
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
        session.recordedUnits = recordedUnits
        session.sourceColumns = table.columns.map(\.name)
        session.importReport = report
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
        // After the demotion, so an out-lap cannot be the lap the sectors are measured on.
        session.sectors = Sectors.analyse(mode: options.sectorMode, session: session)
        session.cornerLabels = options.cornerLabels
        return session
    }

    // MARK: - Time axis

    /// Every importer promises a finite, strictly increasing time axis, but a corrupt file can
    /// break that promise; rows with NaN, infinite or non-increasing times are dropped here so
    /// binary searches and time ranges stay valid.
    /// Drops samples and lap markers outside the trim, keeping the file's own timebase: a
    /// trimmed session's times still read as seconds into the original file, so sync, markers and
    /// anything else pointing into it stay pointing at the same moments.
    static func trimmed(_ table: RawTable, from start: Double?, to end: Double?) -> RawTable {
        guard start != nil || end != nil else { return table }
        let lower = start ?? -.infinity
        let upper = end ?? .infinity
        guard lower <= upper else { return table }
        let keep = table.times.indices.filter { table.times[$0] >= lower && table.times[$0] <= upper }
        guard keep.count != table.times.count else { return table }
        var out = table
        out.times = keep.map { table.times[$0] }
        out.columns = table.columns.map { column in
            var copy = column
            copy.values = keep.map { $0 < column.values.count ? column.values[$0] : nil }
            return copy
        }
        out.lapMarkers = table.lapMarkers.filter { $0.time >= lower && $0.time <= upper }
        return out
    }

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
            return lapsFromMarkers(
                table.lapMarkers.sorted { $0.time < $1.time },
                sessionStart: session.timeRange?.lowerBound ?? 0, sessionEnd: end)
        }
        if let lapChannel = session[.lap] {
            return lapsFromLapNumbers(lapChannel, sessionEnd: end)
        }
        return []
    }

    /// RaceRender semantics: `# Lap N: t` marks the *end* of lap N at time t. Lap 0 starts at
    /// the session start; each subsequent lap starts where the previous ended.
    ///
    /// `sessionStart` is where the data actually begins, not zero: a trimmed session — or a file
    /// whose first sample is not at t=0 — would otherwise report its first lap as starting before
    /// any of its data.
    private static func lapsFromMarkers(
        _ markers: [RawLapMarker], sessionStart: Double, sessionEnd: Double?
    ) -> [Lap] {
        var laps: [Lap] = []
        var start = sessionStart
        for marker in markers where marker.time > sessionStart {
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
