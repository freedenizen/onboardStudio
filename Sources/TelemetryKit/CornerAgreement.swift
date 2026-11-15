import Foundation

/// The corners a session's laps agree on (#585).
///
/// `CornerDetector` reads one lap at a time, and the laps of a session do not all find the same
/// corners: a slight kink after the line, or a lift near the end of the lap, is a corner on some
/// laps and not on others. Everything that numbers corners reads them off one reference lap — the
/// best, usually — so when that lap is one with the kink, the kink is a corner on the map, in the
/// coaching and in the naming sheet, and every count after it is one more than on the other laps.
///
/// So a corner of the reference lap is kept when most of the session's laps find a corner on the
/// same bend, and dropped when only a few do. The other way round — a corner most laps find and
/// the reference lap does not — is left as it is: the reference lap's own distances are what the
/// corners are measured along, and a bend that lap drove straight through has no apex on it.
public enum CornerAgreement {
    /// The fewest complete laps, the reference among them, for a vote to mean anything: with two,
    /// a kink on one is as much the circuit as its absence on the other.
    public static let minimumLaps = 3

    /// The share of the laps that must find a corner for it to be kept: more than this.
    public static let majority = 0.5

    /// `corners`, read off one lap, without those most of `others` — the corners each other lap
    /// found — do not find on the same bend.
    ///
    /// `includesReference` says whether `corners` came from one of the session's laps, which then
    /// votes for its own corners; a profile spliced from several laps or re-based from a rolling
    /// lap does not. Laps whose corners carry no position cannot be compared and do not vote, and
    /// with fewer than `minimumLaps` voting every corner is kept.
    public static func agreed(_ corners: [Corner], by others: [[Corner]], includesReference: Bool = true) -> [Corner] {
        let voters = others.filter { lap in lap.contains { $0.apexLatitude != nil } }
        let laps = voters.count + (includesReference ? 1 : 0)
        guard laps >= minimumLaps, corners.contains(where: { $0.apexLatitude != nil }) else { return corners }
        var found = [Int](repeating: includesReference ? 1 : 0, count: corners.count)
        for lap in voters {
            // One to one, closest pairs first, as names are pinned (#548): a kink a few metres
            // before a real turn must not be "found" on a lap that only has the turn, which it
            // would be if any corner within reach counted — the turn's bend is within reach.
            let pins = lap.compactMap { TurnName(label: "·", corner: $0) }
            for (index, match) in CornerNaming.match(corners, to: pins).enumerated() where match != nil {
                found[index] += 1
            }
        }
        return corners.enumerated().filter { index, corner in
            // A corner placed by distance alone cannot be found on another lap; it stays.
            corner.apexLatitude == nil || Double(found[index]) > Double(laps) * majority
        }.map(\.element)
    }

    /// The corners of every complete lap of `session` but `excluding`, each read on its own.
    static func cornersOfOtherLaps(
        in session: TelemetrySession, excluding number: Int?, options: CornerDetector.Options
    ) -> [[Corner]] {
        session.laps.filter { $0.isComplete && $0.end != nil && $0.number != number }.map {
            CornerDetector.corners(of: $0, in: session, options: options)
        }
    }
}

extension TelemetrySession {
    /// The corners of `reference`, one of this session's laps, that the session's laps agree on
    /// (#585); every corner the lap finds in a project saved before that (`legacyCornersPerLap`).
    public func agreedCorners(of reference: Lap, options: CornerDetector.Options = .init()) -> [Corner] {
        let corners = CornerDetector.corners(of: reference, in: self, options: options)
        guard !legacyCornersPerLap else { return corners }
        let others = CornerAgreement.cornersOfOtherLaps(in: self, excluding: reference.number, options: options)
        return CornerAgreement.agreed(corners, by: others)
    }

    /// The corners of `profile`, read from this session, that the session's laps agree on (#585).
    /// A profile of one of the session's laps votes for its own corners; a spliced or re-based one
    /// is only voted on.
    public func agreedCorners(of profile: LapProfile, options: CornerDetector.Options = .init()) -> [Corner] {
        let corners = CornerDetector.corners(of: profile, options: options)
        guard !legacyCornersPerLap else { return corners }
        let lap = profile.isSpliced ? nil : profile.pieces.first.map(\.lapNumber).flatMap { $0 == 0 ? nil : $0 }
        let others = CornerAgreement.cornersOfOtherLaps(in: self, excluding: lap, options: options)
        return CornerAgreement.agreed(corners, by: others, includesReference: lap != nil)
    }
}
