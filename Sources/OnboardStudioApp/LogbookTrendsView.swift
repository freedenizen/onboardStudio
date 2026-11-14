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
    /// The goals set at the circuit (#461), drawn as dashed lines on the charts.
    var goals: [Goal] = []
    let onOpen: (UUID) -> Void
    @State private var car = ""
    @State private var readingCorners = false
    /// Settings ▸ Units ▸ Speed; with nothing chosen there, the region's (#464).
    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    private var speedSetting: SpeedUnitSetting { SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic }
    /// The corner table's units (#544): the speed unit, and Coaching's distance for it.
    private var cornerFormat: LogbookTrends.CornerFormat { .init(setting: speedSetting) }

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

    /// Both charts' y labels take this width, so their plots, and a session's point and bar, line up.
    private static let yAxisWidth: CGFloat = 52

    private struct Row: Identifiable {
        var id: String { "\(kind)-\(entryID)" }
        var kind: String
        var entryID: UUID
        var position: Double
        var seconds: Double
    }

    private var lapTimes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lap times by session").font(.subheadline.weight(.semibold))
            let layout = layout
            Chart {
                dayRules(layout)
                ForEach(lapGoals, id: \.id) { goal in
                    RuleMark(y: .value("Goal", goal.target.value))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(.secondary)
                }
                ForEach(rows(in: layout)) { row in
                    LineMark(x: .value("Session", row.position), y: .value("Seconds", row.seconds))
                        .foregroundStyle(by: .value("Lap", row.kind))
                    PointMark(x: .value("Session", row.position), y: .value("Seconds", row.seconds))
                        .foregroundStyle(by: .value("Lap", row.kind))
                }
            }
            .chartXScale(domain: layout.domain)
            .chartXAxis { dayAxis(layout) }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text(TimeParsing.lapTimeString(value.as(Double.self) ?? 0)).monospacedDigit()
                            .frame(width: Self.yAxisWidth, alignment: .leading)
                    }
                }
            }
            .chartForegroundStyleScale(["Best": Color.accentColor, "Optimal": Color.green, "Rolling": Color.orange])
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            open(nearest: location, proxy: proxy, geometry: geometry, layout: layout)
                        }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Lap times by visit")
            .accessibilityValue(LogbookTrends.summary(of: points))
            .accessibilityIdentifier("logbook.trends.chart")
            Text("Click a point to open that session.").font(.caption).foregroundStyle(.secondary)
            if !lapGoals.isEmpty {
                Text(goalCaption(lapGoals)).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("logbook.trends.goal")
            }
        }
    }

    private func open(
        nearest location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, layout: TrendsChartLayout
    ) {
        guard let plot = proxy.plotFrame else { return }
        let x = location.x - geometry[plot].origin.x
        guard let position: Double = proxy.value(atX: x), let index = layout.nearestIndex(to: position),
            points.indices.contains(index)
        else { return }
        onOpen(points[index].entryID)
    }

    // MARK: - Corners

    @ViewBuilder private func corners(circuitKey: String) -> some View {
        let comparison = LogbookTrends.cornerComparison(
            for: entries, circuitKey: circuitKey, car: car.isEmpty ? nil : car)
        let trends = comparison?.trends ?? []
        let unread = points.filter { point in
            entries.first { $0.id == point.entryID }?.needsCornerReading ?? point.corners.isEmpty
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Corner by corner: the latest track day").font(.subheadline.weight(.semibold))
            if let comparison {
                Text(Self.caption(of: comparison)).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("logbook.trends.corners.caption")
            }
            if !unread.isEmpty {
                HStack {
                    Text(Self.unreadText(unread))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(readingCorners ? "Reading…" : "Read Their Corners") { readCorners(of: unread) }
                        .disabled(readingCorners)
                        .accessibilityIdentifier("logbook.trends.readCorners")
                }
            }
            if trends.isEmpty {
                Text("No corners read for the latest track day yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                cornerGrid(trends, last: comparison?.previous != nil, best: comparison?.best != nil)
                Text(cornerFormat.note)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("logbook.trends.corners.note")
            }
        }
    }

    /// The corners against the last track day and the personal best; a comparison's columns only
    /// when there is one to make (#426) — no earlier track day, or the latest day holding the
    /// personal best, would leave them dashes.
    private func cornerGrid(_ trends: [LogbookTrends.CornerTrend], last: Bool, best: Bool) -> some View {
        let format = cornerFormat
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("Turn").bold()
                Text("Brake point").bold()
                if last { Text("vs last visit").bold() }
                if best { Text("vs PB").bold() }
                Text("Min speed").bold()
                if last { Text("vs last").bold() }
                if best { Text("vs PB").bold() }
                Text("Time").bold()
                if last { Text("vs last").bold() }
            }
            .font(.caption)
            ForEach(trends) { trend in
                GridRow {
                    Text(trend.label)
                    Text(format.brakePoint(trend.latest?.brakePointMeters))
                    if last { Text(format.brakePointChange(trend.brakePointChange)) }
                    if best { Text(format.brakePointChange(trend.brakePointToBest)) }
                    Text(format.minimumSpeed(trend.latest?.minimumSpeed))
                    if last { Text(format.minimumSpeedChange(trend.minimumSpeedChange)) }
                    if best { Text(format.minimumSpeedChange(trend.minimumSpeedToBest)) }
                    Text(trend.latest.map { String(format: "%.2f s", $0.timeInCorner) } ?? "—")
                    if last { Text(Self.seconds(trend.timeChange)) }
                }
                .font(.callout.monospacedDigit())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("logbook.trends.corner.\(trend.label)")
            }
        }
    }

    /// Why the sessions in `unread` want reading (#438): entered before corners were kept, or
    /// measured by a build whose corner measurement has since been corrected.
    static func unreadText(_ unread: [LogbookTrends.Point]) -> String {
        let missing = unread.filter { $0.corners.isEmpty }.count
        let outdated = unread.count - missing
        func sessions(_ count: Int) -> String { "\(count) session\(count == 1 ? "" : "s")" }
        switch (missing, outdated) {
        case (_, 0): return "\(sessions(missing)) here predate corner records."
        case (0, _): return "\(sessions(outdated)) here were measured before a correction to corner measurement."
        default:
            return "\(sessions(unread.count)) here predate corner records or a correction to corner measurement."
        }
    }

    /// Reads the sessions entered before corners were kept and writes their corners in.
    private func readCorners(of points: [LogbookTrends.Point]) {
        readingCorners = true
        let ids = points.map(\.entryID)
        Task {
            let logbook = AppLogbook.shared
            let tracks = TrackLibrary.app
            await Task.detached(priority: .utility) {
                for id in ids {
                    guard var entry = logbook.entry(id: id), let session = LogbookReferences.load(entry, tracks: tracks)
                    else {
                        continue
                    }
                    entry.readCorners(of: session)
                    try? logbook.save(entry)
                }
            }.value
            LogbookModel.shared.reload()
            readingCorners = false
        }
    }

    static func seconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.magnitude < 0.005 ? "same" : String(format: "%+.2f s", value)
    }
}

/// The two charts' shared x layout (#424), and the consistency chart.
extension LogbookTrendsView {
    /// Sessions evenly spaced in date order, grouped by track day (#424): a time axis squeezed a
    /// day's sessions into a sliver and spent the width on the months between visits.
    private var layout: TrendsChartLayout { LogbookTrends.chartLayout(of: points) }

    private func rows(in layout: TrendsChartLayout) -> [Row] {
        zip(points, layout.positions).flatMap { point, position -> [Row] in
            [("Best", point.best), ("Optimal", point.optimal), ("Rolling", point.rolling)].compactMap { kind, value in
                value.map { Row(kind: kind, entryID: point.entryID, position: position, seconds: $0) }
            }
        }
    }

    /// "12 Jun", with the year when the visits span more than one.
    private func dayLabel(_ date: Date, in layout: TrendsChartLayout) -> String {
        let calendar = Calendar.current
        let years = Set(layout.days.map { calendar.component(.year, from: $0.date) })
        return years.count > 1
            ? date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// One label per track day under the middle of its sessions; every few days when there are
    /// more than fit.
    private func dayAxis(_ layout: TrendsChartLayout) -> some AxisContent {
        let step = max(1, Int((Double(layout.days.count) / 8).rounded(.up)))
        let shown = stride(from: 0, to: layout.days.count, by: step).map { layout.days[$0] }
        return AxisMarks(values: shown.map(\.center)) { value in
            AxisTick()
            AxisValueLabel(anchor: .top) {
                if let center = value.as(Double.self), let day = shown.first(where: { abs($0.center - center) < 0.01 })
                {
                    Text(dayLabel(day.date, in: layout))
                }
            }
        }
    }

    @ChartContentBuilder private func dayRules(_ layout: TrendsChartLayout) -> some ChartContent {
        ForEach(layout.boundaries, id: \.self) { boundary in
            RuleMark(x: .value("Between days", boundary))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    // MARK: - Consistency

    var consistency: some View {
        let layout = layout
        let spreads = zip(points, layout.positions).filter { $0.0.spread != nil }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Consistency: spread of the flying laps").font(.subheadline.weight(.semibold))
            if spreads.isEmpty {
                Text("Needs three flying laps in a session.").font(.callout).foregroundStyle(.secondary)
            } else {
                // One bar per session at the lap chart's positions; by day, a day's bars stacked (#424).
                Chart {
                    dayRules(layout)
                    ForEach(spreads, id: \.0.entryID) { point, position in
                        BarMark(
                            x: .value("Session", position), y: .value("Spread", point.spread ?? 0), width: .fixed(10)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                    ForEach(spreadGoals, id: \.id) { goal in
                        RuleMark(y: .value("Goal", goal.target.value))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: layout.domain)
                .chartXAxis { dayAxis(layout) }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            Text("\(value.as(Double.self) ?? 0, format: .number) s").monospacedDigit()
                                .frame(width: Self.yAxisWidth, alignment: .leading)
                        }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("Consistency by visit")
                .accessibilityValue(
                    spreads.map { point, _ in
                        "\(dayLabel(point.date, in: layout)) \(String(format: "%.2f", point.spread ?? 0)) seconds"
                    }
                    .joined(separator: ", "))
                Text("Lower is steadier: the standard deviation of the laps within ten percent of the best.")
                    .font(.caption).foregroundStyle(.secondary)
                if !spreadGoals.isEmpty {
                    Text(goalCaption(spreadGoals)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Which laps the corner table reads (#426): the best of the latest track day, against the best
    /// of the day before and the personal best.
    static func caption(of comparison: LogbookTrends.CornerComparison) -> String {
        let dates = [comparison.latest, comparison.previous, comparison.best].compactMap { $0?.date }
        let calendar = Calendar.current
        let spansYears = Set(dates.map { calendar.component(.year, from: $0) }).count > 1
        func day(_ point: LogbookTrends.Point) -> String {
            spansYears
                ? point.date.formatted(.dateTime.day().month(.abbreviated).year())
                : point.date.formatted(.dateTime.day().month(.abbreviated))
        }
        func lap(_ point: LogbookTrends.Point) -> String { point.best.map { TimeParsing.lapTimeString($0) } ?? "—" }
        var text = "The best lap of \(day(comparison.latest)), \(lap(comparison.latest))"
        if let previous = comparison.previous {
            text += ", against the best of \(day(previous)), \(lap(previous))"
        }
        if let best = comparison.best {
            text += comparison.previous == nil ? ", against" : ", and"
            text += " your personal best, \(lap(best)) on \(day(best))."
        } else {
            text += comparison.previous == nil ? ": your personal best here." : ". It is your personal best here."
        }
        if comparison.previous == nil { text += " The next track day here is compared with this one." }
        return text
    }
}

// MARK: - Goals on the charts (#461)

extension LogbookTrendsView {
    /// The circuit's goals of one kind, in the car the chart is narrowed to or in any car.
    private func goals(_ matches: (Goal.Target) -> Bool) -> [Goal] {
        goals.filter { goal in
            goal.circuitKey == circuitKey && matches(goal.target)
                && (goal.car.isEmpty || car.isEmpty || goal.car.caseInsensitiveCompare(car) == .orderedSame)
        }
    }

    var lapGoals: [Goal] {
        goals {
            if case .lapTime = $0 { true } else { false }
        }
    }

    var spreadGoals: [Goal] {
        goals {
            if case .consistency = $0 { true } else { false }
        }
    }

    /// "The dashed line is your goal: a 1:40.00 lap in the Miata."
    func goalCaption(_ goals: [Goal]) -> String {
        let titles = goals.map { CircuitGoalsSection.heading($0, speed: .kph).lowercasedFirst }
        let plural = goals.count == 1 ? "line is your goal" : "lines are your goals"
        return "The dashed \(plural): \(titles.joined(separator: "; "))."
    }
}

extension String {
    /// The string with its first letter lower case.
    fileprivate var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
