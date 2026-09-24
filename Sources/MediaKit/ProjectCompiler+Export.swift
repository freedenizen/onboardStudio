import Foundation
import ProjectModel
import TelemetryKit

extension ProjectCompiler {
    // MARK: - Export helpers

    /// The project seconds to export for `range`, or `nil` for everything. Lap ranges use the
    /// first data input that has laps, mapped through that input's sync settings.
    public static func exportRange(_ range: ExportRange, in loaded: LoadedProject, duration: Double)
        -> ClosedRange<Double>?
    {
        switch range {
        case .whole:
            return nil
        case .span(let start, let end):
            let s = min(max(start, 0), duration)
            let e = min(max(end, s), duration)
            return e > s ? s...e : nil
        case .laps(let first, let last):
            for input in loaded.project.dataInputs {
                guard let session = loaded.sessions[input.id], !session.laps.isEmpty else { continue }
                let laps = session.laps.filter { $0.number >= min(first, last) && $0.number <= max(first, last) }
                guard let start = laps.map(\.start).min() else { return nil }
                let end = laps.compactMap { $0.end ?? session.timeRange?.upperBound }.max() ?? start
                let s = min(max(input.sync.projectTime(forInputTime: start), 0), duration)
                let e = min(max(input.sync.projectTime(forInputTime: end), s), duration)
                return e > s ? s...e : nil
            }
            return nil
        case .eachLap:
            // Several files, not one range: `lapExports(_:in:duration:)` says which. As one range
            // it is the span from the first kept lap to the last.
            let laps = lapExports(range, in: loaded, duration: duration)
            guard let first = laps.first, let last = laps.last else { return nil }
            return first.range.lowerBound...last.range.upperBound
        }
    }

    /// The composition to hand to the exporter: overlay-only exports drop the video layers and
    /// clear to the key colour or to transparent.
    public static func prepareForExport(_ compiled: CompiledComposition, settings: ExportSettings)
        -> CompiledComposition
    {
        switch settings.background {
        case .video: return compiled
        case .keyColor(let color): return compiled.overlayOnly(background: color)
        case .transparent: return compiled.overlayOnly(background: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0))
        }
    }
}
