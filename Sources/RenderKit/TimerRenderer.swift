import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Lap timer readout: current / last / best lap or session time, with optional lap number.
public struct TimerRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: TimerParams

    public init(context: ObjectContext, params: TimerParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: rect.height * 0.15, color: params.backgroundColor.cgColor)
        }
        let sample = context.sample(at: time)
        let text = timeText(sample: sample, projectTime: time)
        let label = labelText(sample: sample)
        let padding = rect.height * 0.12
        let labelStyle = TextDrawing.Style(pointSize: rect.height * 0.28, color: params.textColor)
        let valueStyle = TextDrawing.Style.mono(rect.height * 0.5, color: params.textColor)
        if !label.isEmpty {
            TextDrawing.draw(
                label, at: CGPoint(x: rect.minX + padding, y: rect.minY + padding), style: labelStyle, in: cg)
        }
        let valueSize = TextDrawing.size(of: text, style: valueStyle)
        TextDrawing.draw(
            text, at: CGPoint(x: rect.maxX - padding, y: rect.midY - valueSize.height / 2), alignment: .trailing,
            style: valueStyle, in: cg)
    }

    func timeText(sample: TelemetrySample?, projectTime: Double) -> String {
        let seconds: Double? =
            switch params.mode {
            case .currentLap: sample?.lapTiming.elapsedInLap
            case .lastLap: sample?.lapTiming.lastLapTime
            case .bestLap: sample?.lapTiming.bestLapTime
            case .session: sample.map { $0.time - (context.sampler?.session.timeRange?.lowerBound ?? 0) }
            }
        return seconds.map(TimeParsing.lapTimeString) ?? "--:--.--"
    }

    func labelText(sample: TelemetrySample?) -> String {
        var parts: [String] = []
        if let label = params.label, !label.isEmpty {
            parts.append(label)
        } else {
            switch params.mode {
            case .currentLap: parts.append("LAP")
            case .lastLap: parts.append("LAST")
            case .bestLap: parts.append("BEST")
            case .session: parts.append("TIME")
            }
        }
        if params.showLapNumber {
            switch params.mode {
            case .currentLap, .session:
                if let lap = sample?.lapTiming.currentLap { parts.append(String(lap.number)) }
            case .bestLap:
                if let lap = sample?.lapTiming.bestLapNumber { parts.append(String(lap)) }
            case .lastLap:
                if let lap = sample?.lapTiming.currentLap { parts.append(String(max(lap.number - 1, 0))) }
            }
        }
        return parts.joined(separator: " ")
    }
}
