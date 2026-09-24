import Foundation
import ProjectModel
import TelemetryKit

/// One file of an every-lap export (#150): which lap, and the project seconds it covers.
public struct LapExport: Sendable, Equatable {
    public let lap: Int
    public let range: ClosedRange<Double>

    public init(lap: Int, range: ClosedRange<Double>) {
        self.lap = lap
        self.range = range
    }

    /// `Sonoma – Lap 7.mp4`: the project's name and the lap's number, as the file will be called.
    public func fileName(base: String, fileExtension: String) -> String {
        "\(base) – Lap \(lap).\(fileExtension)"
    }
}

/// Which laps an every-lap export keeps: see `ExportRange.eachLap`.
public struct LapSelection: Sendable, Equatable {
    public var completeOnly: Bool
    public var slowerThanBest: Double?

    public init(completeOnly: Bool = true, slowerThanBest: Double? = nil) {
        self.completeOnly = completeOnly
        self.slowerThanBest = slowerThanBest
    }
}

extension ProjectCompiler {
    /// The files an every-lap export writes, in lap order: the laps of the first data input that
    /// has any, kept or left out as the range says, mapped into project time and clipped to it.
    /// Empty for any other kind of range.
    public static func lapExports(_ range: ExportRange, in loaded: LoadedProject, duration: Double) -> [LapExport] {
        guard case .eachLap(let completeOnly, let slowerThanBest) = range else { return [] }
        for input in loaded.project.dataInputs {
            guard let session = loaded.sessions[input.id], !session.laps.isEmpty else { continue }
            return lapExports(
                laps: session.laps, sessionEnd: session.timeRange?.upperBound, sync: input.sync, duration: duration,
                keeping: LapSelection(completeOnly: completeOnly, slowerThanBest: slowerThanBest))
        }
        return []
    }

    /// The same, from the laps themselves.
    public static func lapExports(
        laps: [Lap], sessionEnd: Double?, sync: SyncSettings, duration: Double, keeping selection: LapSelection
    ) -> [LapExport] {
        let completeOnly = selection.completeOnly
        let slowerThanBest = selection.slowerThanBest
        let best = laps.filter(\.isComplete).compactMap(\.duration).min()
        return laps.compactMap { lap -> LapExport? in
            if completeOnly, !lap.isComplete { return nil }
            if let slowerThanBest, let best, let time = lap.duration, time > best * (1 + slowerThanBest) {
                return nil
            }
            guard let end = lap.end ?? sessionEnd else { return nil }
            let start = min(max(sync.projectTime(forInputTime: lap.start), 0), duration)
            let stop = min(max(sync.projectTime(forInputTime: end), start), duration)
            return stop > start ? LapExport(lap: lap.number, range: start...stop) : nil
        }
    }
}

extension ProjectCompiler {
    /// The lap playing at project `time`, with the project seconds it covers, from the first data
    /// input that has laps — complete or not, since a clip of an out-lap is still a clip.
    public static func lap(at time: Double, in loaded: LoadedProject, duration: Double) -> LapExport? {
        lap(
            at: time, in: lapExports(.eachLap(completeOnly: false, slowerThanBest: nil), in: loaded, duration: duration)
        )
    }

    /// The lap in `laps` playing at `time`. On the line between two laps it is the one starting.
    public static func lap(at time: Double, in laps: [LapExport]) -> LapExport? {
        laps.last { $0.range.contains(time) }
    }
}
