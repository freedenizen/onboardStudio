import Foundation
import TelemetryKit

/// One thing to try next time, and where (#330).
public struct PlannedExperiment: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// The corner it is for ("4", "3a"); empty for the lap as a whole.
    public var cornerLabel: String
    /// The experiment, as the driver wants it worded.
    public var text: String

    public init(id: UUID = UUID(), cornerLabel: String, text: String) {
        self.id = id
        self.cornerLabel = cornerLabel
        self.text = text
    }

    public var title: String { cornerLabel.isEmpty ? "Anywhere" : "Turn \(cornerLabel)" }

    private enum CodingKeys: String, CodingKey { case id, cornerLabel, text }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cornerLabel = try c.decodeIfPresent(String.self, forKey: .cornerLabel) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// What to try next session (#330): a few experiments written from the opportunities and edited
/// by the driver, kept with the project and on the circuit's track definition so the next project
/// at that circuit opens knowing what was planned. Instructors end a debrief with three.
public struct NextSessionPlan: Hashable, Codable, Sendable {
    public var experiments: [PlannedExperiment]
    /// The lap the opportunities were read from, and what it was read against.
    public var fromLap: Int?
    public var referencePhrase: String?
    public var made: Date

    public init(
        experiments: [PlannedExperiment], fromLap: Int? = nil, referencePhrase: String? = nil, made: Date = Date()
    ) {
        self.experiments = experiments
        self.fromLap = fromLap
        self.referencePhrase = referencePhrase
        // Whole seconds: the track library writes dates as ISO 8601, and a plan read back from
        // it must still equal the one in the project.
        self.made = Date(timeIntervalSince1970: made.timeIntervalSince1970.rounded())
    }

    /// How many a plan starts with: what an instructor writes down.
    public static let suggestedCount = 3

    /// The top opportunities as experiments: one per corner, in the analysis's own words.
    public static func suggested(
        from analysis: CoachingAnalysis, lapNumber: Int, count: Int = suggestedCount, made: Date = Date()
    ) -> NextSessionPlan {
        let experiments = analysis.opportunities.prefix(max(count, 0)).map { opportunity in
            PlannedExperiment(cornerLabel: opportunity.corner.label, text: opportunity.note.suggestion)
        }
        return NextSessionPlan(
            experiments: Array(experiments), fromLap: lapNumber, referencePhrase: analysis.referencePhrase, made: made)
    }

    /// "Turn 4: brake where lap 5 did… · Turn 7: …", for a status line or a card.
    public var summary: String {
        experiments.map { "\($0.title): \($0.text)" }.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey { case experiments, fromLap, referencePhrase, made }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experiments = try c.decodeIfPresent([PlannedExperiment].self, forKey: .experiments) ?? []
        fromLap = try c.decodeIfPresent(Int.self, forKey: .fromLap)
        referencePhrase = try c.decodeIfPresent(String.self, forKey: .referencePhrase)
        let date = try c.decodeIfPresent(Date.self, forKey: .made) ?? Date(timeIntervalSince1970: 0)
        made = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
    }
}
