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
        let performance = [params.showLaunch, params.showQuarterMile, params.showStop].filter { $0 }.count
        switch params.scope {
        case .session:
            return [params.showBestLap, params.showTopSpeed, params.showOptimalLap, params.showLapCount]
                .filter { $0 }.count + performance
        case .lapAtPlayhead:
            return 1 + [params.showBestLap, params.showTopSpeed, params.showOptimalLap].filter { $0 }.count
                + performance
        }
    }

    /// The rows the card shows at project `time`, in order.
    func rows(at time: Double) -> [Row] {
        guard let session = context.sampler?.session else { return [] }
        switch params.scope {
        case .session:
            return sessionRows(SessionStats(session: session)) + performanceRows(session.performance, at: nil)
        case .lapAtPlayhead:
            let inputTime = context.inputTime(time)
            let performance = performanceRows(session.performance, at: inputTime)
            guard let lap = session.laps.first(where: { $0.isListed && $0.contains(inputTime) }) else {
                return sessionRows(SessionStats(session: session)) + performance
            }
            return lapRows(SessionStats(lap: lap, in: session), lapNumber: lap.number) + performance
        }
    }

    /// 0–60, the quarter mile and 60–0 (#553): of the attempt and the stop at `inputTime` when
    /// there is one there, else the session's best. None when the file's performance runs are not
    /// measured.
    private func performanceRows(_ performance: PerformanceRuns.Result?, at inputTime: Double?) -> [Row] {
        guard let performance else { return [] }
        let metric = context.units.label(for: "speed") != "mph"
        let attempt = inputTime.flatMap { performance.attempt(at: $0) }
        var rows: [Row] = []
        if params.showLaunch {
            let range = PerformanceWording.launch(metric: metric)
            let seconds = attempt.map { $0.speedTimes[range] } ?? performance.best(range)?.seconds
            rows.append(Row(label: range.label, value: seconds.map(PerformanceWording.seconds) ?? "—"))
        }
        if params.showQuarterMile {
            let mark = PerformanceRuns.DragDistance.quarterMile
            let time =
                attempt.map { a in a.distanceTimes[mark].map { ($0, a.trapSpeeds[mark]) } }
                ?? performance.best(mark).map { ($0.seconds, $0.trap) }
            rows.append(
                Row(
                    label: mark.label(metric: metric),
                    value: time.map { PerformanceWording.mark($0.0, trap: $0.1, metric: metric) } ?? "—"))
        }
        if params.showStop {
            let braking = PerformanceWording.braking(metric: metric)
            let here = inputTime.flatMap { performance.stop(at: $0) }.flatMap { $0.from == braking ? $0 : nil }
            let stop = here ?? performance.best(braking)?.stop
            rows.append(
                Row(
                    label: braking.label,
                    value: stop.map { PerformanceWording.distance($0.metres, metric: metric) } ?? "—"))
        }
        return rows
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
