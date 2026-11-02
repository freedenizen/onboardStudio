import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

extension GraphRenderer {
    /// The coaching reference as a lap-axis graph's ghost (#325): a profile already on a distance
    /// grid, which is what the lap axis plots against. Its channels are stored canonically, as the
    /// session's are, so the display conversion is the same; a channel the profile does not carry
    /// has no ghost rather than a wrong one.
    func ghosts(of reference: LapProfile) -> [Trace] {
        params.series.indices.compactMap { index -> Trace? in
            let series = params.series[index]
            guard let role = ChannelValue.role(series.channel), let values = reference.channels[role] else {
                return nil
            }
            let points = zip(reference.distances, values).map { distance, value in
                CGPoint(x: distance, y: context.units.value(value, of: series.channel))
            }
            return Trace(
                points: points, color: params.ghostColor, lineWidth: series.lineWidth, isGhost: true,
                seriesIndex: index)
        }
    }
}
