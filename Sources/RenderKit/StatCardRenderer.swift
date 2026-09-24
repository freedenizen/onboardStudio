import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The headline numbers of a session, or of the lap at the playhead, on one card (#151).
public struct StatCardRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: StatCardParams

    public init(context: ObjectContext, params: StatCardParams) {
        self.context = context
        self.params = params
    }

    /// A line of the card: what it is, and its value.
    struct Row: Equatable {
        let label: String
        let value: String
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 0, rect.height > 0 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(
                rect, radius: min(rect.width, rect.height) * 0.08, color: params.backgroundColor.cgColor)
        }
        let rows = rows(at: time)
        let title = params.title.trimmingCharacters(in: .whitespaces)
        // Sized for the rows the card is set to show, not the ones there are data for: a card
        // does not change size between a lap with a time and one without.
        let lines = Double(max(rows.count, plannedRows)) + (title.isEmpty ? 0 : 1.4)
        guard lines > 0 else { return }
        let padding = rect.height * 0.08
        let lineHeight = (rect.height - padding * 2) / lines
        var y = rect.minY + padding
        if !title.isEmpty {
            var style = context.styled(
                TextDrawing.Style(pointSize: lineHeight * 0.75, color: params.textColor))
            // Shrunk to the card's width rather than running off it: a long circuit name is normal.
            let width = TextDrawing.size(of: title, style: style).width
            let room = rect.width - padding * 2
            if width > room { style.pointSize *= room / width }
            TextDrawing.draw(title, at: CGPoint(x: rect.minX + padding, y: y), style: style, in: cg)
            y += lineHeight * 1.4
        }
        let label = context.styled(
            TextDrawing.Style(pointSize: lineHeight * 0.5, color: params.labelColor, weightBold: false))
        let value = context.styled(.mono(lineHeight * 0.6, color: params.textColor))
        for row in rows {
            TextDrawing.draw(
                row.label, at: CGPoint(x: rect.minX + padding, y: y + lineHeight * 0.12), style: label, in: cg)
            TextDrawing.draw(
                row.value, at: CGPoint(x: rect.maxX - padding, y: y), alignment: .trailing, style: value, in: cg)
            y += lineHeight
        }
    }

    /// How many rows the settings ask for.
    var plannedRows: Int {
        switch params.scope {
        case .session:
            [params.showBestLap, params.showTopSpeed, params.showOptimalLap, params.showLapCount].filter { $0 }.count
        case .lapAtPlayhead:
            1 + [params.showBestLap, params.showTopSpeed, params.showOptimalLap].filter { $0 }.count
        }
    }

    /// The rows the card shows at project `time`, in order.
    func rows(at time: Double) -> [Row] {
        guard let session = context.sampler?.session else { return [] }
        switch params.scope {
        case .session:
            return sessionRows(SessionStats(session: session))
        case .lapAtPlayhead:
            let inputTime = context.inputTime(time)
            guard let lap = session.laps.first(where: { $0.contains(inputTime) }) else {
                return sessionRows(SessionStats(session: session))
            }
            return lapRows(SessionStats(lap: lap, in: session), lapNumber: lap.number)
        }
    }

    private func sessionRows(_ stats: SessionStats) -> [Row] {
        var rows: [Row] = []
        if params.showBestLap, let best = stats.bestLap {
            rows.append(Row(label: "Best lap (\(best.number))", value: TimeParsing.lapTimeString(best.seconds)))
        }
        if params.showTopSpeed, let speed = stats.topSpeed {
            rows.append(Row(label: "Top speed", value: format(speed)))
        }
        if params.showOptimalLap, let optimal = stats.optimalLap {
            rows.append(Row(label: "Optimal lap", value: TimeParsing.lapTimeString(optimal)))
        }
        if params.showLapCount { rows.append(Row(label: "Laps", value: "\(stats.completeLaps)")) }
        return rows
    }

    private func lapRows(_ stats: SessionStats, lapNumber: Int) -> [Row] {
        var rows: [Row] = []
        if let lap = stats.lap {
            rows.append(Row(label: "Lap \(lapNumber)", value: TimeParsing.lapTimeString(lap.seconds)))
            if params.showBestLap, let delta = stats.deltaToBest {
                rows.append(
                    Row(
                        label: "To best",
                        value: abs(delta) < 0.0005 ? "Best lap" : String(format: "%+.2f s", delta)))
            }
        } else {
            rows.append(Row(label: "Lap \(lapNumber)", value: "—"))
        }
        if params.showTopSpeed, let speed = stats.topSpeed {
            rows.append(Row(label: "Top speed", value: format(speed)))
        }
        if params.showOptimalLap, let optimal = stats.optimalLap {
            rows.append(Row(label: "Optimal lap", value: TimeParsing.lapTimeString(optimal)))
        }
        return rows
    }

    /// A speed in the unit this object draws speed in.
    private func format(_ metresPerSecond: Double) -> String {
        let value = context.units.value(metresPerSecond, of: "speed")
        let label = context.units.label(for: "speed") ?? "m/s"
        return "\(Int(value.rounded())) \(label)"
    }
}
