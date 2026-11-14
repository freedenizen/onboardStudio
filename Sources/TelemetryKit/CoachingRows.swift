import Foundation

/// The analysis as words and cells, the same in the window and on the command line.
extension CoachingAnalysis {
    /// "Lap 2 (1:56.90) against your best lap (Lap 4, 1:56.88): 0.01 s behind"
    public func headline(lapNumber: Int, units: CoachingUnits) -> String {
        let format = CoachingNotes.Formatter(units: units)
        let behind = totalLoss >= 0 ? "behind" : "ahead"
        return "Lap \(lapNumber) (\(TimeParsing.lapTimeString(lap.duration, decimals: 2))) against "
            + "\(referencePhrase) (\(reference.label), \(TimeParsing.lapTimeString(reference.duration, decimals: 2))): "
            + "\(format.seconds(abs(totalLoss))) \(behind)" + trafficClause(format: format)
    }

    /// ", 1.80 s of it held up by traffic", when the lap lost time in corners marked as traffic.
    func trafficClause(format: CoachingNotes.Formatter) -> String {
        let lost = trafficLoss
        guard totalLoss > 0, lost >= options.minimumLossSeconds else { return "" }
        let kinds = Set(corners.compactMap { $0.traffic?.onLap == true ? $0.traffic?.kind : nil })
        let kind: TrafficSpan.Kind = kinds == [.flag] ? .flag : .traffic
        return ", \(format.seconds(lost)) of it \(kind.phrase)"
    }

    /// "Spliced from laps 2, 3 and 6" for a spliced reference; `nil` otherwise.
    public var splicedFrom: String? {
        guard reference.isSpliced else { return nil }
        let numbers = reference.pieces.map { String($0.lapNumber) }
        if numbers.count == 1 { return "Spliced from lap \(numbers[0])" }
        return "Spliced from laps " + numbers.dropLast().joined(separator: ", ") + " and \(numbers[numbers.count - 1])"
    }

    /// "Aligned by distance, confidence 1.00"
    public var alignmentLine: String {
        let name: String
        switch delta.alignment {
        case .distance: name = "distance"
        case .fractionOfLap: name = "fraction of lap (approximate)"
        case .position: name = "position"
        }
        return "Aligned by \(name), confidence \(String(format: "%.2f", delta.confidence))"
    }

    /// One row per corner: the numbers to sort by and the words to show.
    public func rows(units: CoachingUnits) -> [CornerRow] {
        let format = CoachingNotes.Formatter(units: units)
        return corners.map { corner in
            let lap = corner.lap
            let reference = corner.reference
            let brake: Double? = {
                guard let own = lap.brakePointMeters, let theirs = reference.brakePointMeters else { return nil }
                return own - theirs
            }()
            let throttle: Double? = {
                guard let own = lap.throttlePickupMeters, let theirs = reference.throttlePickupMeters else {
                    return nil
                }
                return own - theirs
            }()
            let spread = consistency?.spread(ofCorner: corner.index)
            let consistency: CornerRow.Consistency =
                spread.map { $0.isConsistent ? .consistent : .inconsistent } ?? .unknown
            let consistentText: String = {
                guard let spread else { return "–" }
                let word = spread.isConsistent ? "yes" : "no"
                guard let brakeSpread = spread.brakePointSpread else { return word }
                return word + " (\(format.metres(brakeSpread)))"
            }()
            return CornerRow(
                index: corner.index, label: corner.label, timeLost: corner.timeLost,
                phase: corner.traffic?.word ?? corner.worstPhase?.displayName.lowercased() ?? "–",
                brakeDifference: brake, brake: Self.metres(brake, format: format, positive: "early", negative: "late"),
                minimumSpeedDifference: lap.minimumSpeed - reference.minimumSpeed,
                minimumSpeed: Self.speed(lap.minimumSpeed - reference.minimumSpeed, format: format),
                minimumPointDifference: lap.minimumSpeedMeters - reference.minimumSpeedMeters,
                minimumPoint: Self.metres(
                    lap.minimumSpeedMeters - reference.minimumSpeedMeters, format: format, positive: "late",
                    negative: "early"),
                exitSpeedDifference: lap.exitSpeed - reference.exitSpeed,
                exitSpeed: Self.speed(lap.exitSpeed - reference.exitSpeed, format: format),
                throttleDifference: throttle,
                throttle: Self.metres(throttle, format: format, positive: "late", negative: "early"),
                consistency: consistency, consistent: consistentText, traffic: corner.traffic)
        }
    }

    static func metres(_ difference: Double?, format: CoachingNotes.Formatter, positive: String, negative: String)
        -> String
    {
        guard let difference else { return "–" }
        guard abs(difference) >= 1 else { return "same" }
        return "\(format.metres(abs(difference))) \(difference > 0 ? positive : negative)"
    }

    static func speed(_ difference: Double, format: CoachingNotes.Formatter) -> String {
        let text = format.speed(abs(difference))
        return text.hasPrefix("0 ") ? "same" : (difference >= 0 ? "+" : "−") + text
    }
}

/// A corner's line in the table: each difference as a number for sorting and as words.
public struct CornerRow: Identifiable, Sendable, Hashable {
    public var id: Int { index }
    public let index: Int
    public let label: String
    public let timeLost: Double
    public let phase: String
    /// Metres the lap braked before (+) or after (−) the reference; `nil` when either did not brake.
    public let brakeDifference: Double?
    public let brake: String
    public let minimumSpeedDifference: Double
    public let minimumSpeed: String
    /// Metres the slowest point came after (+) or before (−) the reference's.
    public let minimumPointDifference: Double
    public let minimumPoint: String
    public let exitSpeedDifference: Double
    public let exitSpeed: String
    public let throttleDifference: Double?
    public let throttle: String
    public let consistency: Consistency
    public let consistent: String
    /// The traffic or flag mark covering the corner (#571); its phase reads "traffic" or "flag".
    public var traffic: CornerTraffic?

    /// Sort keys for the optional differences: a corner without a reading sorts as "same".
    public var brakeOrder: Double { brakeDifference ?? 0 }
    public var throttleOrder: Double { throttleDifference ?? 0 }

    public enum Consistency: Int, Sendable, Hashable, Comparable {
        case unknown
        case inconsistent
        case consistent

        public static func < (lhs: Consistency, rhs: Consistency) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}
