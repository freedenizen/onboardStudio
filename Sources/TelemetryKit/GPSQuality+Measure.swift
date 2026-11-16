import Foundation

extension GPSQuality {
    /// One position as it arrived.
    struct Fix {
        let time: Double
        let latitude: Double
        let longitude: Double
    }

    /// What `session`'s positions say about themselves; `nil` without positions.
    ///
    /// `latitude` and `longitude` are the channels as the file gave them, before any resampling,
    /// because a resampled channel has the resampler's rate rather than the logger's. Without them
    /// the session's own channels are read.
    public static func measure(
        _ session: TelemetrySession, latitude: Channel? = nil, longitude: Channel? = nil,
        options: Options = Options()
    ) -> GPSQuality? {
        guard let latitude = latitude ?? session[.latitude], let longitude = longitude ?? session[.longitude]
        else { return nil }
        let fixes = fixes(latitude: latitude, longitude: longitude)
        guard fixes.count >= 3 else { return nil }
        let accuracy = median(session[.accuracy]?.values)
        let noise = accuracy ?? options.assumedNoiseMeters
        let logged = loggedRate(in: session).flatMap { median($0.values.filter { $0 > 0 }) }
        var measured = Measurer(fixes: fixes, options: options, noise: noise, loggedRate: logged).measure()
        measured.accuracyMeters = accuracy
        measured.hdop = median(channel(in: session) { $0.unit == .custom("DOP") || $0.name.lowercased() == "hdop" })
        measured.satellites = median(channel(in: session) { $0.name.lowercased() == "satellites" })
        measured.longLaps = longLaps(in: session, factor: options.longLapFactor)
        measured.precisionMeters = (noise * noise + measured.precisionMeters * measured.precisionMeters).squareRoot()
        measured.findings = findings(of: measured, options: options)
        return measured
    }

    /// The GPS's own count of positions a second, when the file logs it: a column the file says came
    /// from the GPS, in hertz. A logger that writes its position into every row, filled in between
    /// fixes, hides the true rate from the times; this is the only place it is still said.
    static func loggedRate(in session: TelemetrySession) -> Channel? {
        let column = session.importReport.columns.first { column in
            column.role != nil && column.unit.symbol.lowercased() == "hz"
                && (column.source?.lowercased().contains("gps") ?? false)
        }
        return column?.role.flatMap { session[$0] }
    }

    /// The positions that arrived, in order. A logger that writes rows faster than its GPS repeats
    /// the last position until the next one; a repeat is not a new position.
    static func fixes(latitude: Channel, longitude: Channel) -> [Fix] {
        var fixes: [Fix] = []
        fixes.reserveCapacity(latitude.count)
        for (time, lat) in zip(latitude.times, latitude.values) {
            guard let lon = longitude.value(at: time), lat.isFinite, lon.isFinite else { continue }
            if let last = fixes.last, last.latitude == lat, last.longitude == lon { continue }
            fixes.append(Fix(time: time, latitude: lat, longitude: lon))
        }
        return fixes
    }

    /// The channel `matches` picks among those the file named itself.
    private static func channel(in session: TelemetrySession, _ matches: (Channel) -> Bool) -> [Double]? {
        session.orderedChannels.first { channel in
            if case .aux = channel.role { return matches(channel) }
            return false
        }?.values
    }

    static func median(_ values: [Double]?) -> Double? {
        let sorted = (values ?? []).filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }

    /// Complete laps about twice the usual length. Needs three laps to know what usual is.
    static func longLaps(in session: TelemetrySession, factor: Double) -> [Int] {
        let laps = session.laps.filter { $0.kind == .lap && $0.isComplete && $0.duration != nil }
        guard laps.count >= 3 else { return [] }
        let lengths = laps.map { lap in
            session[.distance].flatMap { LapComparison.length(of: lap, distance: $0) } ?? lap.duration ?? 0
        }
        guard let usual = median(lengths), usual > 0 else { return [] }
        return zip(laps, lengths).filter { $0.1 >= usual * factor }.map(\.0.number)
    }

    static func findings(of quality: GPSQuality, options: Options) -> [Finding] {
        var found: [Finding] = []
        func rate(_ value: Double?, good: Double, poor: Double, higherIsWorse: Bool) -> Rating? {
            guard let value else { return nil }
            if higherIsWorse { return value > poor ? .poor : value > good ? .fair : nil }
            return value < poor ? .poor : value < good ? .fair : nil
        }
        // Judged as it is shown: a camera's 9.99 Hz is the 10 it says, not "only 10".
        let shownRate = quality.rateHertz >= 2 ? quality.rateHertz.rounded() : quality.rateHertz
        if let rating = rate(shownRate, good: options.goodRateHertz, poor: options.poorRateHertz, higherIsWorse: false)
        {
            found.append(Finding(.rate(hertz: quality.rateHertz, wanted: options.goodRateHertz), rating))
        }
        if let longest = quality.dropouts.map(\.seconds).max() {
            found.append(
                Finding(
                    .dropouts(count: quality.dropouts.count, longestSeconds: longest),
                    longest >= options.poorDropoutSeconds ? .poor : .fair))
        }
        if !quality.jumps.isEmpty {
            found.append(
                Finding(
                    .jumps(count: quality.jumps.count),
                    Double(quality.jumps.count) >= options.poorJumpCount ? .poor : .fair))
        }
        if let meters = quality.accuracyMeters,
            let rating = rate(
                meters, good: options.goodAccuracyMeters, poor: options.poorAccuracyMeters, higherIsWorse: true)
        {
            found.append(Finding(.accuracy(meters: meters), rating))
        }
        if let hdop = quality.hdop,
            let rating = rate(hdop, good: options.goodHDOP, poor: options.poorHDOP, higherIsWorse: true)
        {
            found.append(Finding(.hdop(hdop), rating))
        }
        if let count = quality.satellites,
            let rating = rate(count, good: options.goodSatellites, poor: options.poorSatellites, higherIsWorse: false)
        {
            found.append(Finding(.satellites(count), rating))
        }
        if !quality.longLaps.isEmpty { found.append(Finding(.longLaps(quality.longLaps), .fair)) }
        // Worst first; among equals, in the order above.
        return found.enumerated().sorted { ($0.element.rating, -$0.offset) > ($1.element.rating, -$1.offset) }
            .map(\.element)
    }
}

/// Rate, dropouts, jumps and travel between positions, from the positions alone.
private struct Measurer {
    let fixes: [GPSQuality.Fix]
    let options: GPSQuality.Options
    /// How far a position can be from the truth (m): the logger's own figure, else assumed.
    let noise: Double
    /// Positions a second as the GPS itself logged them, which overrides the times when present.
    let loggedRate: Double?

    struct Segment {
        let interval: Double
        let speed: Double
    }

    func measure() -> GPSQuality {
        let segments = zip(fixes, fixes.dropFirst()).map { from, to in
            let interval = to.time - from.time
            let metres = DerivedChannels.distance(
                lat1: from.latitude, lon1: from.longitude, lat2: to.latitude, lon2: to.longitude)
            return Segment(interval: interval, speed: interval > 0 ? metres / interval : 0)
        }
        let moving = segments.filter { $0.speed > options.movingSpeed && $0.interval > 0 }
        let measured = GPSQuality.median((moving.isEmpty ? segments : moving).map(\.interval)) ?? 1
        let usual = loggedRate.map { 1 / $0 } ?? measured
        let rate = usual > 0 ? 1 / usual : 0
        let gapAfter = max(options.dropoutIntervals * usual, options.dropoutMinimumSeconds)

        var dropouts: [GPSQuality.Gap] = []
        for (index, segment) in segments.enumerated()
        where segment.interval > gapAfter && segment.speed > options.movingSpeed {
            dropouts.append(GPSQuality.Gap(start: fixes[index].time, end: fixes[index + 1].time))
        }

        // How far the car travels between two positions at speed: half of it is how far a brake
        // point can fall from where it is read.
        let speeds = moving.map(\.speed).sorted()
        let fast = speeds.isEmpty ? 0 : speeds[min(speeds.count - 1, speeds.count * 3 / 4)]
        return GPSQuality(
            rateHertz: rate, dropouts: dropouts, jumps: jumps(segments, gapAfter: gapAfter, usual: usual),
            precisionMeters: fast * usual / 2)
    }

    /// Positions the car could not have reached: the speed between two fixes changes by more than
    /// any car can between one fix and the next, beyond what the positions' own error explains.
    func jumps(_ segments: [Segment], gapAfter: Double, usual: Double) -> [Double] {
        var times: [Double] = []
        // An out-and-back jump trips the test on both sides of the stray position; one event.
        let together = max(1, 3 * usual)
        for index in segments.indices.dropFirst() {
            let before = segments[index - 1]
            let after = segments[index]
            guard before.interval > 0, after.interval > 0, before.interval <= gapAfter, after.interval <= gapAfter,
                max(before.speed, after.speed) > options.movingSpeed
            else { continue }
            let allowed =
                options.jumpAcceleration * (before.interval + after.interval) / 2
                + 6 * noise / min(before.interval, after.interval)
            guard abs(after.speed - before.speed) > allowed else { continue }
            let time = fixes[index].time
            if let last = times.last, time - last < together { continue }
            times.append(time)
        }
        return times
    }
}

extension GPSQuality {
    /// `gpsRate`: how many positions arrived in the second up to each tenth of a second, for a gauge
    /// or a graph. A dropout reads zero; so does a parked car on a logger that repeats its last
    /// position, which is not a new one.
    public static func rateChannel(latitude: Channel, longitude: Channel) -> Channel? {
        let times = fixes(latitude: latitude, longitude: longitude).map(\.time)
        guard let first = times.first, let last = times.last, last - first > 1 else { return nil }
        // A tenth of a second, but never more than a few readings a position: a corrupt time an
        // age away from the rest must not ask for billions of them.
        let step = max(0.1, (last - first) / Double(4 * times.count))
        let count = Int(((last - first - 1) / step).rounded(.down)) + 1
        var grid: [Double] = []
        var values: [Double] = []
        grid.reserveCapacity(count)
        values.reserveCapacity(count)
        var lower = 0
        var upper = 0
        for index in 0..<count {
            // From a second in, so the first reading has a whole second behind it.
            let time = first + 1 + Double(index) * step
            while upper < times.count, times[upper] <= time { upper += 1 }
            while lower < upper, times[lower] <= time - 1 { lower += 1 }
            grid.append(time)
            values.append(Double(upper - lower))
        }
        return Channel(
            role: .gpsRate, name: "GPS rate", unit: .custom("Hz"), times: grid, values: values, interpolation: .step)
    }
}

extension SessionBuilder {
    /// The session's GPS quality and its `gpsRate` channel, from the positions as they arrived.
    static func addGPSQuality(
        to session: inout TelemetrySession, latitude: Channel?, longitude: Channel?, options: Options
    ) {
        session.gpsQuality = GPSQuality.measure(
            session, latitude: latitude, longitude: longitude, options: options.gpsQuality)
        guard session[.gpsRate] == nil else { return }
        // The GPS's own figure when it logs one; the times say nothing when positions fill every row.
        if let logged = GPSQuality.loggedRate(in: session) {
            session.add(
                Channel(
                    role: .gpsRate, name: "GPS rate", unit: .custom("Hz"), times: logged.times, values: logged.values,
                    interpolation: logged.interpolation))
            return
        }
        guard let latitude = latitude ?? session[.latitude], let longitude = longitude ?? session[.longitude],
            let rate = GPSQuality.rateChannel(latitude: latitude, longitude: longitude)
        else { return }
        session.add(rate)
    }
}
