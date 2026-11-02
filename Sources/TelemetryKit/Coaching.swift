import Foundation

/// Everything the coaching reading can be tuned by, with defaults that suit a club driver on a
/// GPS logger. None of it is tied to a logger or a circuit.
public struct CoachingOptions: Sendable, Hashable {
    public var corners = CornerDetector.Options()
    public var metrics = CornerMetrics.Options()
    public var stepMeters = 2.0
    /// How the two laps are lined up; `nil` picks by distance within one session and by position
    /// across two.
    public var alignment: LapAlignment?
    /// How many opportunities make the headline.
    public var topCount = 3
    /// A corner losing less than this is not an opportunity.
    public var minimumLossSeconds = 0.03
    /// Brake points closer than this are "the same place".
    public var brakePointToleranceMeters = 5.0
    /// A minimum speed lower than the reference's by less than this fraction is "the same".
    public var minimumSpeedToleranceFraction = 0.02
    /// A minimum speed this far after the reference's is "late".
    public var minimumSpeedLateMeters = 10.0
    public var throttleToleranceMeters = 5.0
    public var coastingToleranceSeconds = 0.3
    /// Peak braking weaker than the reference's by this fraction is "softer".
    public var brakingEffortToleranceFraction = 0.15
    /// Consistency is judged on flying laps: complete laps no more than this fraction slower than
    /// the best. An out lap, an in lap or a lap behind traffic says nothing about repeatability.
    public var flyingLapTolerance = 0.10
    /// A corner whose brake points spread more than this across the session is inconsistent.
    public var consistentBrakeSpreadMeters = 10.0
    /// A corner whose minimum speeds spread more than this fraction of their mean is inconsistent.
    /// Five flying laps of the reference Sonoma session spread 3–10 % by corner; the corners a
    /// coach would call repeatable sit under 5 %.
    public var consistentSpeedSpreadFraction = 0.05

    public init() {}
}

/// What the notes are written in.
public struct CoachingUnits: Sendable, Hashable {
    public var speed: TelemetryUnit
    public var distance: TelemetryUnit

    public init(speed: TelemetryUnit = .kilometersPerHour, distance: TelemetryUnit = .meters) {
        self.speed = speed
        self.distance = distance
    }

    public static let metric = CoachingUnits()
    public static let imperial = CoachingUnits(speed: .milesPerHour, distance: .feet)
}

/// What kind of difference an opportunity is, which picks the suggestion.
public enum OpportunityKind: String, Sendable, Codable, CaseIterable {
    case brakedEarly
    case brakedLate
    case brakedSofter
    case overSlowed
    case minimumTooLate
    case throttleLate
    case coasting
    case slowExit
    case line
}

/// A corner's note: what happened, the evidence, and what to try.
public struct CoachingNote: Sendable, Equatable, Codable {
    /// "Turn 4: 0.31 s lost on entry"
    public let headline: String
    /// "Braked 18 m earlier than your best lap", "Minimum speed 4 km/h lower, 12 m after the apex"
    public let evidence: [String]
    /// What to try next time, phrased as an experiment.
    public let suggestion: String

    public init(headline: String, evidence: [String], suggestion: String) {
        self.headline = headline
        self.evidence = evidence
        self.suggestion = suggestion
    }
}

/// A corner where time went, ranked by how much.
public struct Opportunity: Sendable, Equatable, Codable, Identifiable {
    /// The corner's index, which is stable across references.
    public var id: Int { corner.index }
    /// 1 for the biggest loss.
    public let rank: Int
    public let corner: CornerComparison
    public let phase: CornerPhase
    public let kind: OpportunityKind
    public let timeLost: Double
    public let note: CoachingNote
}

/// Something the reading could not be sure of, for the window to say out loud.
public enum CoachingWarning: Sendable, Equatable, Codable {
    /// The two laps could not be lined up by place and were lined up by fraction of lap.
    case approximateAlignment
    /// Brake and throttle points came from the speed trace, not a pedal.
    case pedalsFromSpeedTrace
    /// A spliced reference changes lap inside these corners, so its speed can step there.
    case seamInCorner(labels: [String])
    /// Fewer than three complete laps: nothing to say about consistency.
    case tooFewLapsForConsistency
}

/// One lap read against a reference: the delta, every corner, the opportunities in order, and
/// how consistent the driver was across the session.
public struct CoachingAnalysis: Sendable {
    public let lap: LapProfile
    public let reference: LapProfile
    /// How the notes name the reference: "your best lap", "lap 5", "Alex (Sunday)".
    public let referencePhrase: String
    public let delta: LapDeltaTrace
    public let corners: [CornerComparison]
    /// Every corner that lost time, biggest first, with its note; `top` is the headline.
    public let opportunities: [Opportunity]
    public let consistency: ConsistencyStats?
    public let warnings: [CoachingWarning]
    public let options: CoachingOptions

    public var top: [Opportunity] { Array(opportunities.prefix(options.topCount)) }
    /// Seconds the lap lost to the reference over the whole lap.
    public var totalLoss: Double { delta.total }

    /// `lap` of `session` against `reference` from the same session. `nil` when the lap or the
    /// reference cannot be profiled (no distance channel, an incomplete lap, no complete laps).
    public static func analyse(
        lap: Lap, reference: CoachingReference, in session: TelemetrySession, units: CoachingUnits = .metric,
        options: CoachingOptions = CoachingOptions()
    ) -> CoachingAnalysis? {
        guard let lapProfile = LapProfile(lap: lap, in: session, stepMeters: options.stepMeters),
            let referenceProfile = reference.resolve(in: session, stepMeters: options.stepMeters)
        else { return nil }
        return analyse(
            lap: lapProfile, in: session, reference: referenceProfile, referencePhrase: reference.phrase,
            sameSession: true, units: units, options: options)
    }

    /// A reference read once and shared by every lap measured against it: its corners and how it
    /// took them, how the notes name it, and the session's consistency when it is the same session
    /// (`CoachingTrack` reads a whole session this way).
    public struct ReferenceReading: Sendable {
        public let profile: LapProfile
        public let corners: [Corner]
        public let metrics: [CornerMetrics]
        public let phrase: String
        public let sameSession: Bool
        public let consistency: ConsistencyStats?

        /// `consistency` is read from `session` when `sameSession`, over the reference's corners.
        public init(
            profile: LapProfile, phrase: String, sameSession: Bool, session: TelemetrySession,
            options: CoachingOptions = CoachingOptions()
        ) {
            self.profile = profile
            self.phrase = phrase
            self.sameSession = sameSession
            corners = CornerDetector.corners(of: profile, options: options.corners)
            metrics = CornerMetrics.measure(corners: corners, of: profile, options: options.metrics)
            consistency = sameSession ? ConsistencyStats.measure(in: session, corners: corners, options: options) : nil
        }
    }

    /// A lap profile against a reference profile, from the same session or another: `sameSession`
    /// picks distance alignment when the options leave it open, and lets consistency be read
    /// from `session`'s other laps.
    public static func analyse(
        lap: LapProfile, in session: TelemetrySession, reference: LapProfile, referencePhrase: String,
        sameSession: Bool, units: CoachingUnits = .metric, options: CoachingOptions = CoachingOptions()
    ) -> CoachingAnalysis? {
        let reading = ReferenceReading(
            profile: reference, phrase: referencePhrase, sameSession: sameSession, session: session, options: options)
        return analyse(lap: lap, in: session, against: reading, units: units, options: options)
    }

    /// The reading with the reference already read.
    public static func analyse(
        lap: LapProfile, in session: TelemetrySession, against reading: ReferenceReading, units: CoachingUnits,
        options: CoachingOptions
    ) -> CoachingAnalysis? {
        let reference = reading.profile
        let referencePhrase = reading.phrase
        let sameSession = reading.sameSession
        let consistency = reading.consistency
        let alignment = options.alignment ?? (sameSession ? .distance : .byPosition)
        guard let delta = LapDeltaTrace(lap: lap, reference: reference, alignment: alignment) else { return nil }
        let referenceCorners = reading.corners
        let referenceMetrics = reading.metrics
        // The same corners on the lap, wherever the alignment says they are.
        let lapCorners = referenceCorners.map { corner in
            Corner(
                startDistance: delta.lapDistance(atReferenceDistance: corner.startDistance),
                endDistance: delta.lapDistance(atReferenceDistance: corner.endDistance),
                apexDistance: delta.lapDistance(atReferenceDistance: corner.apexDistance),
                headingChangeDegrees: corner.headingChangeDegrees, lapLengthMeters: lap.lengthMeters)
        }
        let lapMetrics = CornerMetrics.measure(corners: lapCorners, of: lap, options: options.metrics)
        let comparisons = CornerComparison.compare(
            lap: lapMetrics, reference: referenceMetrics, delta: delta, labels: session.cornerLabels)
        var warnings: [CoachingWarning] = []
        if delta.confidence == 0 && alignment != delta.alignment { warnings.append(.approximateAlignment) }
        if lapMetrics.contains(where: { $0.brakeSource == .speedTrace }) { warnings.append(.pedalsFromSpeedTrace) }
        let seamed = comparisons.filter { comparison in
            reference.seams.contains { seam in
                seam > comparison.reference.corner.startDistance && seam < comparison.reference.corner.endDistance
            }
        }
        if !seamed.isEmpty { warnings.append(.seamInCorner(labels: seamed.map(\.label))) }
        if sameSession, consistency == nil { warnings.append(.tooFewLapsForConsistency) }
        let opportunities = Coaching.rank(
            comparisons, consistency: consistency, referencePhrase: referencePhrase, units: units, options: options)
        return CoachingAnalysis(
            lap: lap, reference: reference, referencePhrase: referencePhrase, delta: delta, corners: comparisons,
            opportunities: opportunities, consistency: consistency, warnings: warnings, options: options)
    }
}

/// The rules that turn corner comparisons into ranked opportunities with notes.
public enum Coaching {
    struct Candidate {
        var comparison: CornerComparison
        var phase: CornerPhase
        var kind: OpportunityKind
    }

    /// Corners that lost time, biggest loss first, each with the phase, the kind of difference
    /// and a note. A corner whose loss the next corner wins back is a compromise that paid, not
    /// an opportunity, and is left out.
    public static func rank(
        _ comparisons: [CornerComparison], consistency: ConsistencyStats?, referencePhrase: String,
        units: CoachingUnits, options: CoachingOptions
    ) -> [Opportunity] {
        var candidates: [Candidate] = []
        for (position, comparison) in comparisons.enumerated() {
            guard comparison.timeLost >= options.minimumLossSeconds, let phase = comparison.worstPhase else { continue }
            if position + 1 < comparisons.count {
                let next = comparisons[position + 1]
                if next.timeLost < 0, -next.timeLost >= comparison.timeLost { continue }
            }
            let kind = kind(of: comparison, phase: phase, options: options)
            candidates.append(Candidate(comparison: comparison, phase: phase, kind: kind))
        }
        candidates.sort { $0.comparison.timeLost > $1.comparison.timeLost }
        return candidates.enumerated().map { offset, candidate in
            let note = CoachingNotes.note(
                CoachingNotes.Context(
                    comparison: candidate.comparison, phase: candidate.phase, kind: candidate.kind,
                    spread: consistency?.spread(ofCorner: candidate.comparison.index), referencePhrase: referencePhrase,
                    units: units, options: options))
            return Opportunity(
                rank: offset + 1, corner: candidate.comparison, phase: candidate.phase, kind: candidate.kind,
                timeLost: candidate.comparison.timeLost, note: note)
        }
    }

    /// The differences between the two readings of a corner that the rules look at.
    struct Differences {
        /// Metres the lap braked before the reference did; nil when either did not brake.
        let brake: Double?
        let softer: Bool
        /// Fraction by which the minimum speed fell short.
        let speedShortfall: Double
        /// Metres the slowest point came after the reference's.
        let minimumLate: Double
        let throttleLate: Double
        let coasting: Double
        let slowerExit: Bool

        init(_ comparison: CornerComparison, options: CoachingOptions) {
            let lap = comparison.lap
            let reference = comparison.reference
            if let own = lap.brakePointMeters, let theirs = reference.brakePointMeters {
                brake = own - theirs
            } else {
                brake = nil
            }
            if let own = lap.peakBrakingG, let theirs = reference.peakBrakingG, theirs > 0 {
                softer = own < theirs * (1 - options.brakingEffortToleranceFraction)
            } else {
                softer = false
            }
            speedShortfall = reference.minimumSpeed > 0 ? 1 - lap.minimumSpeed / reference.minimumSpeed : 0
            minimumLate = lap.minimumSpeedMeters - reference.minimumSpeedMeters
            throttleLate = (lap.throttlePickupMeters ?? 0) - (reference.throttlePickupMeters ?? 0)
            coasting = (lap.coastingSeconds ?? 0) - (reference.coastingSeconds ?? 0)
            slowerExit = lap.exitSpeed < reference.exitSpeed * (1 - options.minimumSpeedToleranceFraction)
        }
    }

    /// What kind of difference the worst phase shows, by the first rule that fits.
    public static func kind(
        of comparison: CornerComparison, phase: CornerPhase, options: CoachingOptions
    ) -> OpportunityKind {
        let differences = Differences(comparison, options: options)
        switch phase {
        case .braking: return brakingKind(differences, options: options)
        case .entry: return entryKind(differences, options: options)
        case .apex: return apexKind(differences, options: options)
        case .exit: return exitKind(differences, options: options)
        }
    }

    static func brakingKind(_ d: Differences, options: CoachingOptions) -> OpportunityKind {
        if let brake = d.brake, brake > options.brakePointToleranceMeters { return .brakedEarly }
        if let brake = d.brake, brake < -options.brakePointToleranceMeters { return .brakedLate }
        if d.softer { return .brakedSofter }
        return d.speedShortfall > options.minimumSpeedToleranceFraction ? .overSlowed : .line
    }

    static func entryKind(_ d: Differences, options: CoachingOptions) -> OpportunityKind {
        if d.speedShortfall > options.minimumSpeedToleranceFraction { return .overSlowed }
        if d.minimumLate > options.minimumSpeedLateMeters { return .minimumTooLate }
        if let brake = d.brake, brake > options.brakePointToleranceMeters { return .brakedEarly }
        return .line
    }

    static func apexKind(_ d: Differences, options: CoachingOptions) -> OpportunityKind {
        if d.minimumLate > options.minimumSpeedLateMeters { return .minimumTooLate }
        if d.coasting > options.coastingToleranceSeconds { return .coasting }
        if d.throttleLate > options.throttleToleranceMeters { return .throttleLate }
        return d.speedShortfall > options.minimumSpeedToleranceFraction ? .overSlowed : .line
    }

    static func exitKind(_ d: Differences, options: CoachingOptions) -> OpportunityKind {
        if d.throttleLate > options.throttleToleranceMeters { return .throttleLate }
        if d.coasting > options.coastingToleranceSeconds { return .coasting }
        return d.slowerExit ? .slowExit : .line
    }
}
