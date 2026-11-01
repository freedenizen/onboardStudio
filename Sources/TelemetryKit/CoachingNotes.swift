import Foundation

/// The sentences. Deterministic phrase templates filled from the numbers, nothing else: the same
/// lap gives the same note every time, and a test can hold the text to a golden.
///
/// Suggestions are experiments, not targets, which is how instructors phrase a debrief ("brake
/// at the 2 board instead of the 3 and see whether exit speed improves"). An inconsistent corner
/// gets consistency first, because every coach says consistency before speed.
public enum CoachingNotes {
    /// What a note is written from.
    public struct Context: Sendable {
        public var comparison: CornerComparison
        public var phase: CornerPhase
        public var kind: OpportunityKind
        public var spread: ConsistencyStats.CornerSpread?
        /// "your best lap", "lap 5", "Alex (Sunday)"
        public var referencePhrase: String
        public var units: CoachingUnits
        public var options: CoachingOptions

        public init(
            comparison: CornerComparison, phase: CornerPhase, kind: OpportunityKind,
            spread: ConsistencyStats.CornerSpread?, referencePhrase: String, units: CoachingUnits,
            options: CoachingOptions
        ) {
            self.comparison = comparison
            self.phase = phase
            self.kind = kind
            self.spread = spread
            self.referencePhrase = referencePhrase
            self.units = units
            self.options = options
        }

        var lap: CornerMetrics { comparison.lap }
        var reference: CornerMetrics { comparison.reference }
        var format: Formatter { Formatter(units: units) }
        /// Metres the lap braked before the reference did; nil when either did not brake.
        var brakeDifference: Double? {
            guard let own = lap.brakePointMeters, let theirs = reference.brakePointMeters else { return nil }
            return own - theirs
        }
        var minimumLate: Double { lap.minimumSpeedMeters - reference.minimumSpeedMeters }
        var throttleLate: Double? {
            guard let own = lap.throttlePickupMeters, let theirs = reference.throttlePickupMeters else { return nil }
            return own - theirs
        }
        var coastingMore: Double? {
            guard let own = lap.coastingSeconds, let theirs = reference.coastingSeconds else { return nil }
            return own - theirs
        }
    }

    public static func note(_ context: Context) -> CoachingNote {
        let format = context.format
        let phase = context.phase.displayName.lowercased()
        let lost = format.seconds(context.comparison.timeLost)
        let headline = "Turn \(context.comparison.label): \(lost) lost on \(phase)"
        var suggestion = suggestion(context)
        if let spread = context.spread, !spread.isConsistent, let brakeSpread = spread.brakePointSpread {
            suggestion =
                "This corner varies lap to lap (brake point spread \(format.metres(brakeSpread))): "
                + "repeat \(context.referencePhrase)'s brake point first, then " + suggestion.lowercasedFirst
        }
        return CoachingNote(headline: headline, evidence: evidence(context), suggestion: suggestion)
    }

    /// The differences worth saying, in driving order: brakes, minimum, throttle, exit.
    static func evidence(_ context: Context) -> [String] {
        let format = context.format
        let options = context.options
        let lap = context.lap
        let reference = context.reference
        let phrase = context.referencePhrase
        var lines: [String] = []
        if let difference = context.brakeDifference {
            if abs(difference) > options.brakePointToleranceMeters {
                let word = difference > 0 ? "earlier" : "later"
                lines.append("Braked \(format.metres(abs(difference))) \(word) than \(phrase)")
            }
        } else if lap.brakePointMeters == nil, reference.brakePointMeters != nil {
            lines.append("Did not brake where \(phrase) did")
        }
        if let own = lap.peakBrakingG, let theirs = reference.peakBrakingG, theirs > 0,
            own < theirs * (1 - options.brakingEffortToleranceFraction)
        {
            lines.append("Peak braking \(format.g(own)) against \(format.g(theirs))")
        }
        let speedDifference = reference.minimumSpeed - lap.minimumSpeed
        let speedFraction = reference.minimumSpeed > 0 ? abs(speedDifference) / reference.minimumSpeed : 0
        let late = context.minimumLate
        if speedFraction > options.minimumSpeedToleranceFraction {
            let word = speedDifference > 0 ? "lower" : "higher"
            var sentence = "Minimum speed \(format.speed(abs(speedDifference))) \(word)"
            if abs(late) > options.minimumSpeedLateMeters {
                sentence += ", \(format.metres(abs(late))) \(late > 0 ? "later" : "earlier")"
            }
            lines.append(sentence)
        } else if late > options.minimumSpeedLateMeters {
            lines.append("Slowest point \(format.metres(late)) later than \(phrase)'s")
        }
        if let throttle = context.throttleLate, abs(throttle) > options.throttleToleranceMeters {
            lines.append("Throttle \(format.metres(abs(throttle))) \(throttle > 0 ? "later" : "earlier")")
        }
        if let coasting = context.coastingMore, coasting > options.coastingToleranceSeconds {
            lines.append("Coasted \(format.seconds(coasting)) longer")
        }
        let exitDifference = reference.exitSpeed - lap.exitSpeed
        if reference.exitSpeed > 0, abs(exitDifference) / reference.exitSpeed > options.minimumSpeedToleranceFraction {
            lines.append("Exit speed \(format.speed(abs(exitDifference))) \(exitDifference > 0 ? "lower" : "higher")")
        }
        if lap.brakeSource == .speedTrace || lap.throttleSource == .speedTrace {
            lines.append("Pedals read from the speed trace")
        }
        return lines
    }

    static func suggestion(_ context: Context) -> String {
        let format = context.format
        let phrase = context.referencePhrase
        switch context.kind {
        case .brakedEarly:
            return "Try braking where \(phrase) did, \(format.metres(context.brakeDifference ?? 0)) later, "
                + "with the same pressure, and see whether the minimum speed comes up."
        case .brakedLate:
            return "Try braking \(format.metres(-(context.brakeDifference ?? 0))) earlier and getting back to the "
                + "throttle sooner; a later brake point only pays if the exit holds up."
        case .brakedSofter:
            return "Try the same brake point with harder initial pressure, easing off as you turn in."
        case .overSlowed:
            let more = context.reference.minimumSpeed - context.lap.minimumSpeed
            return "Try carrying \(format.speed(more)) more through the slowest point: "
                + "release the brakes a little earlier and let the car roll to the apex."
        case .minimumTooLate:
            return "Try trailing the brakes to the apex so the slowest point lands there, not "
                + "\(format.metres(context.minimumLate)) after it, and open the throttle from the apex."
        case .throttleLate:
            return "Try picking the throttle up \(format.metres(context.throttleLate ?? 0)) earlier and feeding it "
                + "in as the wheel unwinds."
        case .coasting:
            return "Try closing the gap between brake and throttle: \(format.seconds(context.coastingMore ?? 0)) off "
                + "both pedals costs more than it saves."
        case .slowExit:
            return "Try a slightly later apex so the car is straight sooner and the throttle can open earlier."
        case .line:
            return "Compare the two laps through this corner in the video; the difference is in the line rather "
                + "than the pedals."
        }
    }

    /// Numbers the way a driver reads them: whole metres or feet, whole km/h or mph, two decimals
    /// of a second, two of a g.
    public struct Formatter: Sendable {
        public let units: CoachingUnits

        public init(units: CoachingUnits) { self.units = units }

        public func metres(_ value: Double) -> String {
            let converted = TelemetryUnit.meters.convert(value, to: units.distance) ?? value
            return "\(Int(converted.rounded())) \(units.distance.symbol)"
        }

        /// `value` in m/s, shown in the speed unit.
        public func speed(_ value: Double) -> String {
            let converted = TelemetryUnit.metersPerSecond.convert(value, to: units.speed) ?? value
            return "\(Int(converted.rounded())) \(units.speed.symbol)"
        }

        public func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }

        public func g(_ value: Double) -> String { String(format: "%.2f g", value) }
    }
}

extension String {
    /// The string with its first letter lowercased, for joining a sentence onto a clause.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
