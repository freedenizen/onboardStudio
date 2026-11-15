import Charts
import ProjectModel
import SwiftUI

/// What every Trends chart draws along its x axis (#424): a label per track day and a rule
/// between days, so the lap charts and the performance charts read the same way.
extension TrendsChartLayout {
    /// "12 Jun", with the year when the sessions span more than one.
    func label(_ date: Date) -> String {
        let calendar = Calendar.current
        let years = Set(days.map { calendar.component(.year, from: $0.date) })
        return years.count > 1
            ? date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// One label per track day under the middle of its sessions; every few days when there are
    /// more than fit.
    var dayAxis: some AxisContent {
        let step = max(1, Int((Double(days.count) / 8).rounded(.up)))
        let shown = stride(from: 0, to: days.count, by: step).map { days[$0] }
        return AxisMarks(values: shown.map(\.center)) { value in
            AxisTick()
            AxisValueLabel(anchor: .top) {
                if let center = value.as(Double.self), let day = shown.first(where: { abs($0.center - center) < 0.01 })
                {
                    Text(label(day.date))
                }
            }
        }
    }

    /// A dashed rule between one track day and the next.
    @ChartContentBuilder var dayRules: some ChartContent {
        ForEach(boundaries, id: \.self) { boundary in
            RuleMark(x: .value("Between days", boundary))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    /// The session under a click at `location` on a chart laid out by this layout.
    func index(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        guard let plot = proxy.plotFrame, let position: Double = proxy.value(atX: location.x - geometry[plot].origin.x)
        else { return nil }
        return nearestIndex(to: position)
    }
}
