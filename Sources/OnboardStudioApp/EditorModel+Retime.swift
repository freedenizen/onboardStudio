import Foundation
import ProjectModel
import TelemetryKit

/// Slowing, speeding and holding the video from the editor (#443). Retimes live in project time,
/// so nothing else on the timeline moves; the preview and the export play them, the overlays
/// with the picture.
extension EditorModel {
    /// Whether In to Out is a range that can be given a speed.
    var canRetimeInOut: Bool { inOutRange != nil }

    /// Plays In to Out at `rate` (1 = normal speed again).
    func setSpeedOfInOut(_ rate: Double) {
        guard let range = inOutRange else {
            statusMessage = "Mark In and Out first: the speed applies to the range between them."
            return
        }
        let name = abs(rate - 1) < 1e-9 ? "Normal Speed" : (rate < 1 ? "Slow Down" : "Speed Up")
        edit(name) { $0.setSpeed(rate, over: range) }
        statusMessage =
            abs(rate - 1) < 1e-9
            ? "\(clock(range.lowerBound)) to \(clock(range.upperBound)) plays at normal speed."
            : "\(clock(range.lowerBound)) to \(clock(range.upperBound)) plays at \(Retime.percent(rate))."
    }

    /// ⇧H: holds the frame at the playhead, picture and overlays, for `seconds`.
    func holdFrameAtPlayhead(seconds: Double = 1) {
        guard duration > 0 else { return }
        let time = currentTime
        edit("Add Hold") { $0.addHold(at: time, seconds: seconds) }
        statusMessage = "\(Retime.holdLabel(seconds)) at \(clock(time))."
    }

    func changeSpeed(of retime: Retime, to rate: Double) {
        edit("Change Speed") { $0.change(retime: retime.id, rate: rate) }
    }

    func changeHold(of retime: Retime, to seconds: Double) {
        edit("Change Hold") { $0.change(retime: retime.id, holdSeconds: seconds) }
    }

    func remove(_ retime: Retime) {
        let name = if case .hold = retime.kind { "Remove Hold" } else { "Remove Speed Change" }
        edit(name) { $0.removeRetime(retime.id) }
    }

    private func clock(_ seconds: Double) -> String { TimeParsing.lapTimeString(seconds) }
}
