import Foundation

/// A coaching analysis described for a file or a bug report: what `onboard coach --json` prints.
/// Values and words only, never the samples.
public struct CoachingReport: Encodable, Sendable {
    public struct ProfileSummary: Encodable, Sendable {
        public let label: String
        public let lengthMeters: Double
        public let duration: Double
        public let pieces: [LapProfile.Piece]
        public let sources: [String: LapProfile.Source]

        init(_ profile: LapProfile) {
            label = profile.label
            lengthMeters = profile.lengthMeters
            duration = profile.duration
            pieces = profile.pieces
            sources = Dictionary(uniqueKeysWithValues: profile.sources.map { ($0.key.identifier, $0.value) })
        }
    }

    public let lap: ProfileSummary
    public let reference: ProfileSummary
    public let referencePhrase: String
    public let alignment: LapAlignment
    public let confidence: Double
    public let totalLoss: Double
    /// Seconds of `totalLoss` lost in corners marked as traffic or a flag (#571).
    public let trafficLoss: Double
    public let opportunities: [Opportunity]
    public let corners: [CornerComparison]
    public let consistency: ConsistencyStats?
    public let warnings: [CoachingWarning]

    public init(_ analysis: CoachingAnalysis) {
        lap = ProfileSummary(analysis.lap)
        reference = ProfileSummary(analysis.reference)
        referencePhrase = analysis.referencePhrase
        alignment = analysis.delta.alignment
        confidence = analysis.delta.confidence
        totalLoss = analysis.totalLoss
        trafficLoss = analysis.trafficLoss
        opportunities = analysis.opportunities
        corners = analysis.corners
        consistency = analysis.consistency
        warnings = analysis.warnings
    }
}
