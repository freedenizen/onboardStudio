import Foundation

extension CornerMetrics {
    /// Reads every corner of `corners` off `lap`. Corner distances are metres into this lap, so
    /// corners found on a reference lap of the same length apply directly, as sectors do.
    ///
    /// A corner that wraps the start/finish line is not measured: its braking and its exit are in
    /// different laps, and one profile holds one lap. It is left out rather than guessed at.
    public static func measure(corners: [Corner], of lap: LapProfile, options: Options = Options()) -> [CornerMetrics] {
        guard lap.count >= 4, let speed = lap.channels[.speed] else { return [] }
        let reader = Reader(lap: lap, speed: speed, options: options)
        var measured: [CornerMetrics] = corners.indices.compactMap { index in
            let corner = corners[index]
            guard !corner.wrapsStartFinish else { return nil }
            let previousEnd = index > 0 && !corners[index - 1].wrapsStartFinish ? corners[index - 1].endDistance : 0
            let nextStart = index + 1 < corners.count ? corners[index + 1].startDistance : lap.lengthMeters
            let from = max(previousEnd, corner.startDistance - options.approachMeters)
            let to = min(max(nextStart, corner.endDistance), lap.lengthMeters)
            guard to > corner.endDistance - 1e-6, from < corner.startDistance + 1e-6 else { return nil }
            return reader.measure(corner, index: index, searchRange: from...to)
        }
        // The straight after a corner belongs to its exit: a slow exit costs time all the way
        // to the next brake point, which is where the next corner's braking phase begins. The
        // last corner's exit runs to the end of the lap.
        for index in measured.indices {
            let next = index + 1 < measured.count ? measured[index + 1].phaseStart : lap.lengthMeters
            guard let exit = measured[index].phases[.exit] else { continue }
            measured[index].phases[.exit] = exit.lowerBound...max(exit.upperBound, next)
        }
        return measured
    }

    /// Everything about one lap the per-corner reading needs, worked out once.
    struct Reader {
        let lap: LapProfile
        let speed: [Double]
        let options: Options
        let brakeOn: [Bool]?
        let brakeSource: Source?
        let throttleOn: [Bool]?
        let throttleFull: [Bool]?
        let throttleSource: Source?
        let longitudinalG: [Double]?
        let lateralG: [Double]?
        let gapPoints: Int

        init(lap: LapProfile, speed: [Double], options: Options) {
            self.lap = lap
            self.speed = speed
            self.options = options
            gapPoints = Int((options.pedalGapMeters / lap.stepMeters).rounded())
            longitudinalG = lap.channels[.longitudinalG]
            lateralG = lap.channels[.lateralG]

            if let brake = lap.channels[.brake], let on = Self.above(brake, fraction: options.brakeOnFraction) {
                brakeOn = on
                brakeSource = .brakeChannel
            } else if let pressure = lap.channels[.brakePressureFront] ?? lap.channels[.brakePressureRear],
                let on = Self.above(pressure, fraction: options.brakeOnFraction)
            {
                brakeOn = on
                brakeSource = .brakePressure
            } else if let longitudinalG {
                brakeOn = longitudinalG.map { $0 <= -options.brakingDecelerationG }
                brakeSource = lap.source(of: .longitudinalG) == .recorded ? .accelerometer : .speedTrace
            } else {
                brakeOn = nil
                brakeSource = nil
            }

            if let throttle = lap.channels[.throttle],
                let on = Self.above(throttle, fraction: options.throttleOnFraction)
            {
                throttleOn = on
                throttleFull = Self.above(throttle, fraction: options.fullThrottleFraction)
                throttleSource = .throttleChannel
            } else if let longitudinalG {
                throttleOn = longitudinalG.map { $0 >= options.acceleratingG }
                throttleFull = nil
                throttleSource = lap.source(of: .longitudinalG) == .recorded ? .accelerometer : .speedTrace
            } else {
                throttleOn = nil
                throttleFull = nil
                throttleSource = nil
            }
        }

        /// `values` above `fraction` of their own range; `nil` for a channel that never moves,
        /// which says nothing about the pedal.
        static func above(_ values: [Double], fraction: Double) -> [Bool]? {
            guard let low = values.min(), let high = values.max(), high - low > 0 else { return nil }
            let threshold = low + (high - low) * fraction
            return values.map { $0 > threshold }
        }

        func index(_ distance: Double) -> Int {
            min(max(Int((distance / lap.stepMeters).rounded()), 0), lap.count - 1)
        }

        func distance(_ index: Int) -> Double { lap.distances[index] }

        func measure(_ corner: Corner, index cornerIndex: Int, searchRange: ClosedRange<Double>) -> CornerMetrics {
            let searchFrom = index(searchRange.lowerBound)
            let searchTo = index(searchRange.upperBound)
            let turnIn = index(corner.startDistance)
            let cornerEnd = index(corner.endDistance)
            let apex = corner.apexDistance

            // The slowest point, looked for a little either side of the geometric corner: an
            // early apex puts it before turn-in.
            let margin = Int((25 / lap.stepMeters).rounded())
            let slowFrom = max(searchFrom, turnIn - margin)
            var slowTo = min(searchTo, cornerEnd + margin)
            // Braking that begins after the corner has ended is for the next one: past it the speed
            // falls into the next braking zone, and a flat-out corner took that braking, and the
            // speed in it, as its own — a brake point after its apex (#438).
            if let brakeOn, cornerEnd < slowTo,
                let next = Self.runs(brakeOn, from: cornerEnd, to: slowTo, mergingGapsUnder: gapPoints)
                    .first(where: { $0.lowerBound > cornerEnd })
            {
                slowTo = max(slowFrom, next.lowerBound - 1)
            }
            let slowest = (slowFrom...slowTo).min { speed[$0] < speed[$1] } ?? turnIn

            var metrics = CornerMetrics(
                corner: corner, index: cornerIndex, searchRange: searchRange, entrySpeed: speed[turnIn],
                minimumSpeed: speed[slowest], minimumSpeedMeters: distance(slowest) - apex, exitSpeed: speed[cornerEnd],
                timeInCorner: lap.elapsed[cornerEnd] - lap.elapsed[turnIn], phases: [:])

            let brakeRun = brakeRun(from: searchFrom, to: slowest)
            if let run = brakeRun {
                metrics.brakePointMeters = apex - distance(run.lowerBound)
                metrics.brakeSource = brakeSource
                metrics.brakeReleaseMeters = distance(run.upperBound) - apex
                metrics.peakBrakingG = longitudinalG.map { -($0[run].min() ?? 0) }
            }

            let pickup = throttlePickup(from: max(turnIn, slowest - margin / 5), to: searchTo)
            if let pickup {
                metrics.throttlePickupMeters = distance(pickup) - apex
                metrics.throttleSource = throttleSource
                if let throttleFull, let full = (pickup...searchTo).first(where: { throttleFull[$0] }) {
                    metrics.fullThrottleMeters = distance(full) - apex
                }
            }

            if let lateralG {
                let peak = lateralG[turnIn...cornerEnd].map(abs).max() ?? 0
                metrics.peakLateralG = peak
                if let run = brakeRun, peak > 0 {
                    let cornering = options.corneringLateralFraction * peak
                    metrics.trailBrakingMeters =
                        Double(run.filter { abs(lateralG[$0]) >= cornering }.count) * lap.stepMeters
                }
            }
            metrics.coastingSeconds = coasting(from: brakeRun?.lowerBound ?? turnIn, to: cornerEnd)
            metrics.steeringSmoothness = steeringSmoothness(from: turnIn, to: cornerEnd)
            metrics.phases = Self.phases(
                brakePoint: brakeRun.map { distance($0.lowerBound) }, turnIn: corner.startDistance,
                slowest: distance(slowest), pickup: pickup.map(distance),
                exitEnd: metrics.fullThrottleMeters.map {
                    max(corner.endDistance, min(apex + $0, searchRange.upperBound))
                }
                    ?? corner.endDistance)
            return metrics
        }

        /// The braking that led into the corner: the last application before the slowest point.
        func brakeRun(from searchFrom: Int, to slowest: Int) -> ClosedRange<Int>? {
            guard let brakeOn, brakeSource != nil,
                var run = Self.runs(brakeOn, from: searchFrom, to: slowest, mergingGapsUnder: gapPoints).last
            else { return nil }
            // Deceleration read off a smoothed trace crosses its threshold some metres after the
            // pedal went down. Walking back to where it crosses half the threshold lands within a
            // couple of metres of the real onset, whatever the braking effort.
            if brakeSource == .speedTrace || brakeSource == .accelerometer, let longitudinalG {
                var lower = run.lowerBound
                let half = -options.brakingDecelerationG / 2
                while lower > searchFrom, longitudinalG[lower - 1] <= half { lower -= 1 }
                run = lower...run.upperBound
            }
            return run
        }

        /// Where the throttle came back after the slowest point.
        func throttlePickup(from: Int, to: Int) -> Int? {
            guard let throttleOn, throttleSource != nil else { return nil }
            return Self.runs(throttleOn, from: from, to: to, mergingGapsUnder: gapPoints).first?.lowerBound
        }

        /// Seconds with neither pedal applied; only recorded pedals can say.
        func coasting(from: Int, to: Int) -> Double? {
            guard let brakeOn, let throttleOn, brakeSource == .brakeChannel || brakeSource == .brakePressure,
                throttleSource == .throttleChannel, to > from
            else { return nil }
            var coasting = 0.0
            for point in from..<to where !brakeOn[point] && !throttleOn[point] {
                coasting += lap.elapsed[point + 1] - lap.elapsed[point]
            }
            return coasting
        }

        func steeringSmoothness(from: Int, to: Int) -> Double? {
            guard let steering = lap.channels[.steeringAngle], to > from else { return nil }
            let changes = (from..<to).map { (steering[$0 + 1] - steering[$0]) / lap.stepMeters }
            return (changes.reduce(0) { $0 + $1 * $1 } / Double(changes.count)).squareRoot()
        }

        /// Maximal stretches of `on` within `from...to`, gaps shorter than `gap` points bridged.
        static func runs(_ on: [Bool], from: Int, to: Int, mergingGapsUnder gap: Int) -> [ClosedRange<Int>] {
            guard from <= to, from >= 0, to < on.count else { return [] }
            var runs: [ClosedRange<Int>] = []
            var index = from
            while index <= to {
                guard on[index] else {
                    index += 1
                    continue
                }
                var upper = index
                while upper + 1 <= to, on[upper + 1] { upper += 1 }
                if let last = runs.last, index - last.upperBound - 1 < gap {
                    runs[runs.count - 1] = last.lowerBound...upper
                } else {
                    runs.append(index...upper)
                }
                index = upper + 1
            }
            return runs
        }

        /// The phases, each starting where the one before ends so they tile without gaps.
        static func phases(
            brakePoint: Double?, turnIn: Double, slowest: Double, pickup: Double?, exitEnd: Double
        ) -> [CornerPhase: ClosedRange<Double>] {
            let start = min(brakePoint ?? turnIn, turnIn)
            let entryEnd = max(turnIn, slowest)
            let apexEnd = max(entryEnd, pickup ?? slowest)
            let end = max(apexEnd, exitEnd)
            return [
                .braking: start...turnIn,
                .entry: turnIn...entryEnd,
                .apex: entryEnd...apexEnd,
                .exit: apexEnd...end,
            ]
        }
    }
}
