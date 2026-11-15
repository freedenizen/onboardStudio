import Charts
import ProjectModel
import SwiftUI
import TelemetryKit

/// Trends ▸ Performance (#553): every measured session's best launch and quarter mile, one line
/// per car, and each car's personal bests. Read across the whole logbook, never by circuit: a
/// straight line is the car's, not the venue's.
struct PerformanceTrendsSection: View {
    /// The measured sessions, oldest first (`PerformanceTrends.points`).
    let points: [PerformanceTrends.Point]
    /// km/h measures rather than mph.
    let metric: Bool
    let onOpen: (UUID) -> Void

    private var launchLabel: String { PerformanceWording.launch(metric: metric).label }
    private var stopLabel: String { PerformanceWording.braking(metric: metric).label }
    private var layout: TrendsChartLayout { TrendsChartLayout(dates: points.map(\.date)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance").font(.title3.weight(.semibold))
                Text(PerformanceTrends.summary(of: points, metric: metric))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("logbook.trends.performance.summary")
            }
            bests
            if points.count < 2 {
                Text("A second measured session starts the charts.").font(.callout).foregroundStyle(.secondary)
            } else {
                chart("\(launchLabel) by session", value: \.launch, identifier: "launch")
                chart("Quarter mile by session", value: \.quarterMile, identifier: "quarterMile")
                Text("Quarter mile with a \(PerformanceWording.rollout). Click a point to open that session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logbook.trends.performance")
    }

    // MARK: - Personal bests per car

    private var bests: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Personal bests by car").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Car")
                    Text(launchLabel)
                    Text("Quarter mile")
                    Text("\(stopLabel) distance")
                }
                .font(.caption.bold())
                ForEach(PerformanceTrends.bests(in: points)) { car in
                    GridRow {
                        Text(car.car.isEmpty ? "No car" : car.car)
                        best(car.launch, measure: launchLabel) { PerformanceWording.seconds($0.value) }
                        best(car.quarterMile, measure: "Quarter mile") {
                            PerformanceWording.mark($0.value, trap: $0.trap, metric: metric)
                        }
                        best(car.stop, measure: "\(stopLabel) distance") {
                            PerformanceWording.distance($0.value, metric: metric)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .accessibilityIdentifier("logbook.trends.performance.car.\(car.car.isEmpty ? "none" : car.car)")
                }
            }
            Text("Click a best to open the session that set it.").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A best and its day, opening its session; a dash when the car never reached the measure.
    @ViewBuilder private func best(
        _ record: PerformanceTrends.Record?, measure: String, text: (PerformanceTrends.Record) -> String
    ) -> some View {
        if let record {
            let value = text(record)
            let day = layout.label(record.date)
            Button {
                onOpen(record.entryID)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                    Text(day).font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.link)
            .accessibilityLabel("\(measure) \(value) on \(day)")
            .help("Open the session of \(day)")
        } else {
            Text("—").foregroundStyle(.secondary).accessibilityLabel("\(measure) not measured")
        }
    }

    // MARK: - The charts

    private struct Row: Identifiable {
        var id: UUID
        var car: String
        var position: Double
        var seconds: Double
    }

    /// One measure's best per session, a line per car, at the sessions' day-grouped positions.
    @ViewBuilder private func chart(
        _ title: String, value: KeyPath<PerformanceTrends.Point, Double?>, identifier: String
    ) -> some View {
        let layout = layout
        let rows = zip(points, layout.positions).compactMap { point, position in
            point[keyPath: value].map {
                Row(id: point.entryID, car: point.car.isEmpty ? "No car" : point.car, position: position, seconds: $0)
            }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Chart(rows) { row in
                    LineMark(x: .value("Session", row.position), y: .value("Seconds", row.seconds))
                        .foregroundStyle(by: .value("Car", row.car))
                    PointMark(x: .value("Session", row.position), y: .value("Seconds", row.seconds))
                        .foregroundStyle(by: .value("Car", row.car))
                }
                .chartXScale(domain: layout.domain)
                .chartXAxis { layout.dayAxis }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            Text(PerformanceWording.seconds(value.as(Double.self) ?? 0)).monospacedDigit()
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let index = layout.index(at: location, proxy: proxy, geometry: geometry),
                                    points.indices.contains(index)
                                else { return }
                                onOpen(points[index].entryID)
                            }
                    }
                }
                .frame(height: 160)
                .accessibilityLabel(title)
                .accessibilityValue(
                    rows.map { row in
                        "\(row.car), \(layout.label(date(of: row.id))), \(PerformanceWording.seconds(row.seconds))"
                    }
                    .joined(separator: "; ")
                )
                .accessibilityIdentifier("logbook.trends.performance.\(identifier)")
            }
        }
    }

    private func date(of entryID: UUID) -> Date { points.first { $0.entryID == entryID }?.date ?? .distantPast }
}
