import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The coaching note for the corner in play (#323): "Turn 4: 0.31 s lost on entry", the evidence,
/// and what to try — from `leadSeconds` before the brake point to `holdSeconds` after the corner.
///
/// Reads the project's coaching track for this object's data input. Without a session at all (a
/// template's picture) it draws an example card, so a template that carries one shows what it is.
public struct CornerCalloutRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: CornerCalloutParams

    public init(context: ObjectContext, params: CornerCalloutParams) {
        self.context = context
        self.params = params
    }

    /// What the card says.
    public struct Card: Equatable, Sendable {
        public var headline: String
        /// Time lost (+) or gained (−), which colours the headline.
        public var timeLost: Double
        public var evidence: [String]
        public var suggestion: String?
    }

    private var units: CoachingUnits { context.speedUnit == .mph ? .imperial : .metric }

    /// The card at `inputTime`, or `nil` on a straight, between laps, or without coaching.
    public func card(at inputTime: Double) -> Card? {
        guard let track = context.coaching,
            let moment = track.moment(
                atInputTime: inputTime, leadSeconds: params.leadSeconds, holdSeconds: params.holdSeconds)
        else { return nil }
        return card(for: moment.comparison, analysis: moment.analysis)
    }

    func card(for comparison: CornerComparison, analysis: CoachingAnalysis) -> Card? {
        let options = analysis.options
        let lost = comparison.timeLost
        if params.onlyOpportunities, lost < options.minimumLossSeconds { return nil }
        let format = CoachingNotes.Formatter(units: units)
        let headline: String
        var suggestion: String?
        if lost >= options.minimumLossSeconds, let phase = comparison.worstPhase {
            headline = "Turn \(comparison.label): \(format.seconds(lost)) lost on \(phase.displayName.lowercased())"
            let kind = Coaching.kind(of: comparison, phase: phase, options: options)
            let note = CoachingNotes.Context(
                comparison: comparison, phase: phase, kind: kind,
                spread: analysis.consistency?.spread(ofCorner: comparison.index),
                referencePhrase: analysis.referencePhrase, units: units, options: options)
            suggestion = params.showSuggestion ? CoachingNotes.suggestion(note) : nil
        } else if lost <= -options.minimumLossSeconds {
            headline = "Turn \(comparison.label): \(format.seconds(-lost)) gained"
        } else {
            headline = "Turn \(comparison.label): level with \(analysis.referencePhrase)"
        }
        let evidenceContext = CoachingNotes.Context(
            comparison: comparison, phase: comparison.worstPhase ?? .entry, kind: .line, spread: nil,
            referencePhrase: analysis.referencePhrase, units: units, options: options)
        let evidence = params.showEvidence ? CoachingNotes.evidence(evidenceContext) : []
        return Card(headline: headline, timeLost: lost, evidence: evidence, suggestion: suggestion)
    }

    /// What a template's picture shows: a card with nothing behind it.
    static let example = Card(
        headline: "Turn 4: 0.31 s lost on entry", timeLost: 0.31,
        evidence: ["Braked 18 m earlier than your best lap", "Minimum speed 4 km/h lower, 12 m later"],
        suggestion: "Try braking where your best lap did, 18 m later, with the same pressure, and see whether "
            + "the minimum speed comes up.")

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 16, rect.height > 16 else { return }
        let shown: Card
        if context.sampler == nil, context.coaching == nil {
            shown = Self.example
        } else if let live = card(at: context.inputTime(time)) {
            shown = live
        } else {
            return
        }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: min(rect.width, rect.height) * 0.08, color: params.backgroundColor.cgColor)
        }
        let padding = min(rect.width, rect.height) * 0.08
        let inner = rect.insetBy(dx: padding, dy: padding)
        var lines = Self.layout(shown, in: inner, params: params, styled: context.styled)
        // Nothing may run past the card: lines that do not fit are dropped from the bottom.
        lines.removeAll { $0.y + $0.height > inner.maxY + 0.5 }
        for line in lines {
            TextDrawing.draw(line.text, at: CGPoint(x: inner.minX, y: line.y), style: line.style, in: cg)
        }
    }

    /// One drawn line of text.
    struct Line {
        let text: String
        let y: Double
        let height: Double
        let style: TextDrawing.Style
    }

    /// The card's lines laid out top to bottom inside `rect`: the headline sized to fit the width,
    /// then the evidence, then the suggestion wrapped to the width.
    static func layout(
        _ card: Card, in rect: CGRect, params: CornerCalloutParams, styled: (TextDrawing.Style) -> TextDrawing.Style
    ) -> [Line] {
        let base = rect.height * 0.14
        let headlineColor =
            card.timeLost > 0 ? params.behindColor : card.timeLost < 0 ? params.aheadColor : params.textColor
        var headline = styled(TextDrawing.Style(pointSize: base * 1.15, color: headlineColor))
        headline.pointSize = fitted(card.headline, style: headline, width: rect.width)
        var lines: [Line] = []
        var y = rect.minY
        func add(_ text: String, _ style: TextDrawing.Style, gap: Double) {
            let height = TextDrawing.size(of: text, style: style).height
            lines.append(Line(text: text, y: y, height: height, style: style))
            y += height + gap
        }
        add(card.headline, headline, gap: base * 0.35)
        let body = styled(TextDrawing.Style(pointSize: base * 0.8, color: params.textColor, weightBold: false))
        // Three lines of evidence leave room for what to try; without a suggestion there is room
        // for all of it.
        for evidence in card.evidence.prefix(card.suggestion == nil ? 6 : 3) {
            for wrapped in wrap("• " + evidence, style: body, width: rect.width) { add(wrapped, body, gap: base * 0.1) }
        }
        if let suggestion = card.suggestion {
            y += base * 0.25
            let quiet = styled(
                TextDrawing.Style(pointSize: base * 0.72, color: params.secondaryColor, weightBold: false))
            for wrapped in wrap(suggestion, style: quiet, width: rect.width) { add(wrapped, quiet, gap: base * 0.1) }
        }
        return lines
    }

    /// The largest point size at or below the style's at which `text` fits `width` on one line.
    static func fitted(_ text: String, style: TextDrawing.Style, width: Double) -> Double {
        var style = style
        let measured = TextDrawing.size(of: text, style: style).width
        guard measured > width, measured > 0 else { return style.pointSize }
        style.pointSize = max(6, style.pointSize * width / measured)
        return style.pointSize
    }

    /// `text` broken into lines no wider than `width`, at word boundaries.
    static func wrap(_ text: String, style: TextDrawing.Style, width: Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if TextDrawing.size(of: candidate, style: style).width <= width || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
