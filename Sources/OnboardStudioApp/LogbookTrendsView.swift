import Charts
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// Am I getting quicker, and where (#353): the lap times across visits to a circuit as a chart,
/// how consistent each visit was, and every corner against the previous visit and the personal
/// best. A point opens its session.
struct LogbookTrendsView: View {
    let entries: [LogbookEntry]
    let circuitKey: String?
    let circuitTitle: String
    let onOpen: (UUID) -> Void
    @State private var car = ""
    @State private var readingCorners = false

    private var cars: [String] {
        Array(Set(entries.filter { LogbookFilter.circuitKey(of: $0) == circuitKey }.map(\.car).filter { !$0.isEmpty }))
            .sorted()
    }

    private var points: [LogbookTrends.Point] {
        guard let circuitKey else { return [] }
        return LogbookTrends.points(for: entries, circuitKey: circuitKey, car: car.isEmpty ? nil : car)
    }

    var body: some View {
        if let circuitKey {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if points.count < 2 {
                        ContentUnavailableView(
                            "Two Visits Make a Trend", systemImage: "chart.line.uptrend.xyaxis",
                            description: Text(emptyDescription))
                    } else {
                        lapTimes
                        consistency
                    }
                    corners(circuitKey: circuitKey)
                    if cars.count >= 2 {
                        Divider()
                        CarVersusCarSection(entries: entries, circuitKey: circuitKey, cars: cars)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("logbook.trends")
        } else {
            ContentUnavailableView(
                "Choose a Circuit", systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Trends read across the visits to one circuit: pick one in the sidebar."))
        }
    }

    private var emptyDescription: String {
        let count = points.count == 1 ? "one session" : "no sessions"
        let inCar = car.isEmpty ? "" : " in the \(car)"
        return "The logbook has \(count) at \(circuitTitle)\(inCar). Add another track day there."
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(circuitTitle).font(.title3.weight(.semibold))
                Text(LogbookTrends.summary(of: points)).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("logbook.trends.summary")
            }
            Spacer()
            if cars.count > 1 {
                Picker("Car", selection: $car) {
                    Text("Every car").tag("")
                    ForEach(cars, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("logbook.trends.car")
            }
        }
    }

    // MARK: - Lap times across visits

    private struct Row: Identifiable {
        var id: String { "\(kind)-\(entryID)" }
        var kind: String
        var entryID: UUID
        var date: Date
        var seconds: Double
    }

    private var rows: [Row] {
        points.flatMap { point -> [Row] in
            [("Best", point.best), ("Optimal", point.optimal), ("Rolling", point.rolling)].compactMap { kind, value in
                value.map { Row(kind: kind, entryID: point.entryID, date: point.date, seconds: $0) }
            }
        }
    }

    private var lapTimes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lap times by visit").font(.subheadline.weight(.semibold))
            Chart(rows) { row in
                LineMark(x: .value("Visit", row.date), y: .value("Seconds", row.seconds))
                    .foregroundStyle(by: .value("Lap", row.kind))
                PointMark(x: .value("Visit", row.date), y: .value("Seconds", row.seconds))
                    .foregroundStyle(by: .value("Lap", row.kind))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(TimeParsing.lapTimeString(value.as(Double.self) ?? 0)).monospacedDigit() }
                }
            }
            .chartForegroundStyleScale(["Best": Color.accentColor, "Optimal": Color.green, "Rolling": Color.orange])
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in open(nearest: location, proxy: proxy, geometry: geometry) }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Lap times by visit")
            .accessibilityValue(LogbookTrends.summary(of: points))
            .accessibilityIdentifier("logbook.trends.chart")
            Text("Click a point to open that session.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func open(nearest location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plot = proxy.plotFrame else { return }
        let x = location.x - geometry[plot].origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        let nearest = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        guard let point = nearest else { return }
        onOpen(point.entryID)
    }

    // MARK: - Consistency

    private var consistency: some View {
        let spreads = points.filter { $0.spread != nil }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Consistency: spread of the flying laps").font(.subheadline.weight(.semibold))
            if spreads.isEmpty {
                Text("Needs three flying laps in a session.").font(.callout).foregroundStyle(.secondary)
            } else {
                Chart(spreads) { point in
                    BarMark(x: .value("Visit", point.date, unit: .day), y: .value("Spread", point.spread ?? 0))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
                .chartYAxisLabel("s")
                .frame(height: 120)
                .accessibilityLabel("Consistency by visit")
                .accessibilityValue(
                    spreads.map { "\(LogbookTrends.month($0.date)) \(String(format: "%.2f", $0.spread ?? 0)) seconds" }
                        .joined(separator: ", "))
                Text("Lower is steadier: the standard deviation of the laps within ten percent of the best.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Corners

    @ViewBuilder private func corners(circuitKey: String) -> some View {
        let trends = LogbookTrends.cornerTrends(for: entries, circuitKey: circuitKey, car: car.isEmpty ? nil : car)
        let unread = points.filter { $0.corners.isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            Text("Corner by corner: the latest visit").font(.subheadline.weight(.semibold))
            if !unread.isEmpty {
                HStack {
                    Text("\(unread.count) session\(unread.count == 1 ? "" : "s") here predate corner records.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(readingCorners ? "Reading…" : "Read Their Corners") { readCorners(of: unread) }
                        .disabled(readingCorners)
                        .accessibilityIdentifier("logbook.trends.readCorners")
                }
            }
            if trends.isEmpty {
                Text("No corners read for the latest visit yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        Text("Turn").bold()
                        Text("Brake point").bold()
                        Text("vs last visit").bold()
                        Text("vs PB").bold()
                        Text("Min speed").bold()
                        Text("vs last").bold()
                        Text("vs PB").bold()
                        Text("Time").bold()
                        Text("vs last").bold()
                    }
                    .font(.caption)
                    ForEach(trends) { trend in
                        GridRow {
                            Text(trend.label)
                            Text(trend.latest?.brakePointMeters.map { "\(Int($0.rounded())) m" } ?? "—")
                            Text(Self.metres(trend.brakePointChange))
                            Text(Self.metres(trend.brakePointToBest))
                            Text(trend.latest.map { Self.speed($0.minimumSpeed) } ?? "—")
                            Text(Self.speedDelta(trend.minimumSpeedChange))
                            Text(Self.speedDelta(trend.minimumSpeedToBest))
                            Text(trend.latest.map { String(format: "%.2f s", $0.timeInCorner) } ?? "—")
                            Text(Self.seconds(trend.timeChange))
                        }
                        .font(.callout.monospacedDigit())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("logbook.trends.corner.\(trend.label)")
                    }
                }
                Text(
                    "Brake point: positive means later than the other visit. Minimum speed in km/h. Time: negative "
                        + "means quicker through the corner."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Reads the sessions entered before corners were kept and writes their corners in.
    private func readCorners(of points: [LogbookTrends.Point]) {
        readingCorners = true
        let ids = points.map(\.entryID)
        Task {
            let logbook = AppLogbook.shared
            await Task.detached(priority: .utility) {
                for id in ids {
                    guard var entry = logbook.entry(id: id), let session = LogbookReferences.load(entry) else {
                        continue
                    }
                    entry.corners = LogbookEntry.cornerRecords(of: session)
                    try? logbook.save(entry)
                }
            }.value
            LogbookModel.shared.reload()
            readingCorners = false
        }
    }

    static func metres(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.magnitude < 0.5 ? "same" : String(format: "%+.0f m", value)
    }

    static func speed(_ metresPerSecond: Double) -> String { String(format: "%.0f km/h", metresPerSecond * 3.6) }

    static func speedDelta(_ value: Double?) -> String {
        guard let value else { return "—" }
        let kph = value * 3.6
        return kph.magnitude < 0.5 ? "same" : String(format: "%+.0f km/h", kph)
    }

    static func seconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.magnitude < 0.005 ? "same" : String(format: "%+.2f s", value)
    }
}
