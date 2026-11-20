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
            Chart {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    LineMark(x: .value("Session", index), y: .value("Share", point.meanUsed * 100))
                        .foregroundStyle(by: .value("Reading", "Grip used braking and turning"))
                    PointMark(x: .value("Session", index), y: .value("Share", point.meanUsed * 100))
                        .foregroundStyle(by: .value("Reading", "Grip used braking and turning"))
                    LineMark(x: .value("Session", index), y: .value("Share", point.nearLimit * 100))
                        .foregroundStyle(by: .value("Reading", "Lap near the limit"))
                    PointMark(x: .value("Session", index), y: .value("Share", point.nearLimit * 100))
                        .foregroundStyle(by: .value("Reading", "Lap near the limit"))
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let share = value.as(Int.self) { Text("\(share)%") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: Array(points.indices)) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self), points.indices.contains(index) {
                            Text(points[index].date.formatted(.dateTime.day().month(.abbreviated)))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let frame = proxy.plotFrame,
                                let index = proxy.value(atX: location.x - geometry[frame].origin.x, as: Double.self)
                            else { return }
                            let nearest = Int(index.rounded())
                            if points.indices.contains(nearest) { onOpen(points[nearest].entryID) }
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
