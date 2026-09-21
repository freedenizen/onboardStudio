import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The lap in progress, sector by sector: each sector's time and how it compares with a
/// reference, with the theoretical best lap on the end.
///
/// The sector the car is in shows its running time, sectors already finished show what they took,
/// and sectors still to come are blank — the same way a timing screen fills in across a lap.
public struct SectorPanelRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: SectorPanelParams

    public init(context: ObjectContext, params: SectorPanelParams) {
        self.context = context
        self.params = params
    }

    struct Layout {
        let rect: CGRect
        var height: Double { rect.height }
        var label: Double { height * 0.22 }
        var time: Double { height * 0.44 }
        var delta: Double { height * 0.24 }
        var labelY: Double { rect.minY + height * 0.04 }
        var timeY: Double { rect.minY + height * 0.27 }
        var deltaY: Double { rect.minY + height * 0.75 }
    }

    /// One column of the strip.
    struct Cell {
        let label: String
        let time: Double?
        let delta: Double?
        let isCurrent: Bool
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 8, rect.height > 8 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: rect.height * 0.15, color: params.backgroundColor.cgColor)
        }
        let cells = cells(at: context.inputTime(time))
        guard !cells.isEmpty else { return }
        let layout = Layout(rect: rect)
        let width = rect.width / Double(cells.count)
        for (index, cell) in cells.enumerated() {
            draw(cell, in: cg, layout: layout, centre: rect.minX + width * (Double(index) + 0.5))
        }
    }

    /// What the strip shows at `inputTime`: one cell per sector, plus the theoretical lap.
    ///
    /// Empty without a session, without sectors, or when only one sector was found — a single
    /// sector is the lap, which the Timing Panel already shows.
    func cells(at inputTime: Double) -> [Cell] {
        guard let session = context.sampler?.session, let analysis = session.sectors, analysis.count > 1,
            let status = analysis.status(at: inputTime, session: session)
        else { return [] }
        let shown = held(status, analysis: analysis, at: inputTime, session: session) ?? status
        let reference = referenceTimes(analysis, status: shown, session: session)
        var cells = (0..<analysis.count).map { index -> Cell in
            let isCurrent = index == shown.sectorIndex
            // The sector in progress shows its running time; one not yet reached shows nothing.
            let time = isCurrent ? shown.elapsedInSector : shown.times[index]
            // A delta only means something once the sector is finished.
            let delta = shown.times[index].flatMap { done in reference[index].map { done - $0 } }
            return Cell(label: SectorLayout.name(of: index), time: time, delta: delta, isCurrent: isCurrent)
        }
        if params.showTheoretical {
            cells.append(
                Cell(
                    label: params.theoreticalLabel, time: analysis.theoreticalLapTime, delta: nil, isCurrent: false))
        }
        return cells
    }

    /// The lap that has just finished, for a few seconds after the line.
    ///
    /// Without this the final sector is never readable: it completes at the instant the car
    /// crosses, and by the next frame the panel is showing the new lap. A timing screen holds the
    /// lap it has just timed for the same reason. `nil` once the hold is over, or when the lap in
    /// progress is the first one.
    func held(_ status: SectorStatus, analysis: SectorAnalysis, at inputTime: Double, session: TelemetrySession)
        -> SectorStatus?
    {
        guard params.holdPreviousSeconds > 0, let lap = session.laps.lap(containing: inputTime),
            inputTime - lap.start < params.holdPreviousSeconds,
            let previous = analysis.laps.last(where: { $0.lapNumber < status.lapNumber }),
            previous.times.allSatisfy({ $0 != nil })
        else { return nil }
        // Every sector finished, so none is in progress: an index past the last one.
        return SectorStatus(
            lapNumber: previous.lapNumber, sectorIndex: analysis.count, elapsedInSector: 0, times: previous.times)
    }

    /// The times each sector is measured against.
    func referenceTimes(_ analysis: SectorAnalysis, status: SectorStatus, session: TelemetrySession) -> [Double?] {
        switch params.reference {
        case .bestSector:
            return analysis.bestTimes
        case .sessionBestLap:
            return analysis.times(ofLap: LapDeltas.sessionBest(in: session)?.number)
        case .previousLap:
            // The lap before the one in progress, which is not always `number − 1`: an out-lap
            // that timed no sector is not in the analysis at all.
            return analysis.times(ofLap: analysis.laps.last { $0.lapNumber < status.lapNumber }?.lapNumber)
        }
    }

    // MARK: - Drawing

    private func draw(_ cell: Cell, in cg: CGContext, layout: Layout, centre: Double) {
        let timeColour = cell.isCurrent && params.highlightCurrent ? params.currentColor : params.textColor
        if params.showLabels {
            text(
                cell.label, at: CGPoint(x: centre, y: layout.labelY), size: layout.label,
                color: cell.isCurrent && params.highlightCurrent ? params.currentColor : params.labelColor, in: cg)
        }
        if params.display.showsTime {
            let string = cell.time.map { TimeParsing.lapTimeString($0, decimals: decimals) } ?? "–"
            text(string, at: CGPoint(x: centre, y: layout.timeY), size: layout.time, color: timeColour, in: cg)
        }
        guard params.display.showsDelta, let delta = cell.delta else { return }
        // In the delta-only mode the delta takes the time's place, and its size with it.
        let showingTime = params.display.showsTime
        text(
            TimeParsing.deltaString(delta, decimals: decimals),
            at: CGPoint(x: centre, y: showingTime ? layout.deltaY : layout.timeY),
            size: showingTime ? layout.delta : layout.time,
            color: colour(for: delta), in: cg)
    }

    /// Ahead, behind, or neither. A delta that rounds away to `0.00` — which is what the lap
    /// holding the best sector always shows — is drawn in the text colour rather than being
    /// called a loss on the last digit of floating point.
    func colour(for delta: Double) -> RGBAColor {
        let scale = pow(10.0, Double(decimals))
        let rounded = (delta * scale).rounded() / scale
        if rounded == 0 { return params.textColor }
        return rounded > 0 ? params.behindColor : params.aheadColor
    }

    var decimals: Int { max(1, min(3, params.decimals)) }

    /// Centred text with the same black surround the other panels use, so the strip stays
    /// readable over a bright sky or a white kerb.
    private func text(_ string: String, at point: CGPoint, size: Double, color: RGBAColor, in cg: CGContext) {
        let style = TextDrawing.Style(pointSize: size, color: color)
        if params.outline {
            let width = max(1, size * 0.06)
            var back = style
            back.color = .black
            for dx in [-width, 0, width] {
                for dy in [-width, 0, width] where dx != 0 || dy != 0 {
                    TextDrawing.draw(
                        string, at: CGPoint(x: point.x + dx, y: point.y + dy), alignment: .center, style: back, in: cg)
                }
            }
        }
        TextDrawing.draw(string, at: point, alignment: .center, style: style, in: cg)
    }
}
