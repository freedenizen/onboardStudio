import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Lap timer readout: current / last / best lap, session or video time, time of day, or the
/// delta to the best lap, with an optional lap number.
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
        let readout = self.readout(sample: sample, projectTime: time)
        let label = labelText(sample: sample)
        let padding = rect.height * 0.12
        let labelStyle = TextDrawing.Style(pointSize: rect.height * 0.28, color: params.textColor)
        let valueStyle = TextDrawing.Style.mono(rect.height * 0.5, color: readout.color ?? params.textColor)
        if !label.isEmpty {
            TextDrawing.draw(
                label, at: CGPoint(x: rect.minX + padding, y: rect.minY + padding), style: labelStyle, in: cg)
        }
        let valueSize = TextDrawing.size(of: readout.text, style: valueStyle)
        TextDrawing.draw(
            readout.text, at: CGPoint(x: rect.maxX - padding, y: rect.midY - valueSize.height / 2),
            alignment: .trailing, style: valueStyle, in: cg)
    }

    struct Readout {
        var text: String
        var color: RGBAColor?
    }

    func readout(sample: TelemetrySample?, projectTime: Double) -> Readout {
        let decimals = max(1, min(3, params.decimals))
        switch params.mode {
        case .currentLap:
            return Readout(text: lapTime(sample?.lapTiming.elapsedInLap, decimals: decimals), color: nil)
        case .lastLap:
            return Readout(text: lapTime(sample?.lapTiming.lastLapTime, decimals: decimals), color: nil)
        case .bestLap:
            return Readout(text: lapTime(sample?.lapTiming.bestLapTime, decimals: decimals), color: nil)
        case .session:
            let seconds = sample.map { $0.time - (context.sampler?.session.timeRange?.lowerBound ?? 0) }
            return Readout(text: lapTime(seconds, decimals: decimals), color: nil)
        case .projectTime:
            return Readout(text: lapTime(projectTime, decimals: decimals), color: nil)
        case .timeOfDay:
            return Readout(text: timeOfDay(sample: sample) ?? "--:--:--", color: nil)
        case .deltaToBest:
            guard let sample, let session = context.sampler?.session,
                let delta = LapComparison.deltaToBest(at: sample.time, session: session)
            else { return Readout(text: "--.--", color: nil) }
            let text = TimeParsing.deltaString(delta, decimals: decimals)
            let color = text.hasPrefix("−") ? params.aheadColor : (text.hasPrefix("+") ? params.behindColor : nil)
            return Readout(text: text, color: color)
        }
    }

    func lapTime(_ seconds: Double?, decimals: Int) -> String {
        seconds.map { TimeParsing.lapTimeString($0, decimals: decimals) } ?? "--:--.--"
    }

    /// Wall-clock time from the data: absolute when the file carries epoch timestamps, otherwise
    /// relative to the session's recorded start.
    func timeOfDay(sample: TelemetrySample?) -> String? {
        guard let sample, let session = context.sampler?.session else { return nil }
        let epoch: Double
        if let created = session.info.createdAt {
            epoch = created.timeIntervalSince1970 + (sample.time - (session.timeRange?.lowerBound ?? sample.time))
        } else if sample.time > 1_000_000_000 {
            epoch = sample.time
        } else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch).formatted(Self.clockFormat)
    }

    static let clockFormat = Date.FormatStyle(date: .omitted, time: .standard).hour(.twoDigits(amPM: .omitted))

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
            case .projectTime: parts.append("VIDEO")
            case .timeOfDay: parts.append("CLOCK")
            case .deltaToBest: parts.append("DELTA")
            }
        }
        if params.showLapNumber {
            switch params.mode {
            case .currentLap, .session, .deltaToBest, .projectTime, .timeOfDay:
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
