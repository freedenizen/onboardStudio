import Foundation

/// A card that says, as the car arrives at each corner, what the coaching found there (#323):
/// the headline, the evidence and what to try, against the project's coaching reference.
///
/// One object follows the whole lap; it appears `leadSeconds` before the corner's brake point,
/// stays through the corner and `holdSeconds` after it, and is blank on the straights.
public struct CornerCalloutParams: Hashable, Codable, Sendable {
    /// Seconds before the brake point the card appears.
    public var leadSeconds: Double
    /// Seconds after the corner's end the card stays up.
    public var holdSeconds: Double
    /// The lines of evidence under the headline ("Braked 18 m earlier than your best lap").
    public var showEvidence: Bool
    /// What to try, under the evidence.
    public var showSuggestion: Bool
    /// Only corners where time was lost; off, every corner gets its card, including the ones
    /// where time was gained.
    public var onlyOpportunities: Bool
    public var textColor: RGBAColor
    public var secondaryColor: RGBAColor
    public var aheadColor: RGBAColor
    public var behindColor: RGBAColor
    public var backgroundColor: RGBAColor

    public init(
        leadSeconds: Double = 3,
        holdSeconds: Double = 2,
        showEvidence: Bool = true,
        showSuggestion: Bool = true,
        onlyOpportunities: Bool = false,
        textColor: RGBAColor = .white,
        secondaryColor: RGBAColor = RGBAColor(red: 0.8, green: 0.8, blue: 0.8),
        aheadColor: RGBAColor = RGBAColor(red: 0.13, green: 0.75, blue: 0.25),
        behindColor: RGBAColor = RGBAColor(red: 0.88, green: 0.19, blue: 0.19),
        backgroundColor: RGBAColor = .faceDark
    ) {
        self.leadSeconds = max(0, leadSeconds)
        self.holdSeconds = max(0, holdSeconds)
        self.showEvidence = showEvidence
        self.showSuggestion = showSuggestion
        self.onlyOpportunities = onlyOpportunities
        self.textColor = textColor
        self.secondaryColor = secondaryColor
        self.aheadColor = aheadColor
        self.behindColor = behindColor
        self.backgroundColor = backgroundColor
    }

    private enum CodingKeys: String, CodingKey {
        case leadSeconds, holdSeconds, showEvidence, showSuggestion, onlyOpportunities
        case textColor, secondaryColor, aheadColor, behindColor, backgroundColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CornerCalloutParams()
        leadSeconds = try c.decodeIfPresent(Double.self, forKey: .leadSeconds) ?? d.leadSeconds
        holdSeconds = try c.decodeIfPresent(Double.self, forKey: .holdSeconds) ?? d.holdSeconds
        showEvidence = try c.decodeIfPresent(Bool.self, forKey: .showEvidence) ?? d.showEvidence
        showSuggestion = try c.decodeIfPresent(Bool.self, forKey: .showSuggestion) ?? d.showSuggestion
        onlyOpportunities = try c.decodeIfPresent(Bool.self, forKey: .onlyOpportunities) ?? d.onlyOpportunities
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        secondaryColor = try c.decodeIfPresent(RGBAColor.self, forKey: .secondaryColor) ?? d.secondaryColor
        aheadColor = try c.decodeIfPresent(RGBAColor.self, forKey: .aheadColor) ?? d.aheadColor
        behindColor = try c.decodeIfPresent(RGBAColor.self, forKey: .behindColor) ?? d.behindColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
    }
}

extension Project {
    /// Whether anything in the project draws from the coaching analysis, which is then read once
    /// per compile for every data input.
    public var needsCoaching: Bool {
        displayObjects.contains { object in
            switch object.kind {
            case .cornerCallout: return true
            case .trackMap(let params): return params.usesCoaching
            default: return false
            }
        }
    }
}
