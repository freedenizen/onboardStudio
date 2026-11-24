import Charts
import ProjectModel
import SwiftUI

/// Grip over visits (#558): each session's share of the car's grip used braking and turning, and of
/// the lap near the limit, read against the car's grip in that session's conditions.
struct GripTrendsSection: View {
    let points: [GripTrends.Point]
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Grip: how much of the car's grip was used").font(.subheadline.weight(.semibold))
            if let summary = GripTrends.summary(of: points) {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("logbook.trends.grip.summary")
            }
            // Laid out as the lap charts are (#424): a label per track day and a rule between
            // days. A label per session wrote the same date under five points of one day (#670).
            let layout = TrendsChartLayout(dates: points.map(\.date))
            Chart {
                layout.dayRules
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let position = layout.positions[index]
                    LineMark(x: .value("Session", position), y: .value("Share", point.meanUsed * 100))
                        .foregroundStyle(by: .value("Reading", "Grip used braking and turning"))
                    PointMark(x: .value("Session", position), y: .value("Share", point.meanUsed * 100))
                        .foregroundStyle(by: .value("Reading", "Grip used braking and turning"))
                    LineMark(x: .value("Session", position), y: .value("Share", point.nearLimit * 100))
                        .foregroundStyle(by: .value("Reading", "Lap near the limit"))
                    PointMark(x: .value("Session", position), y: .value("Share", point.nearLimit * 100))
                        .foregroundStyle(by: .value("Reading", "Lap near the limit"))
                }
            }
            .chartXScale(domain: layout.domain)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let share = value.as(Int.self) { Text("\(share)%") } }
                }
            }
            .chartXAxis { layout.dayAxis }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let nearest = layout.index(at: location, proxy: proxy, geometry: geometry),
                                points.indices.contains(nearest)
                            else { return }
                            onOpen(points[nearest].entryID)
                        }
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Grip used over the sessions")
            .accessibilityValue(GripTrends.summary(of: points) ?? "")
            .accessibilityIdentifier("logbook.trends.grip")
            Text(
                "Read against the most grip the car has shown in conditions like each session's. Click a point to "
                    + "open that session."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
