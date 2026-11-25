import ProjectModel
import SwiftUI
import TelemetryKit

/// A session's standing starts and stops in the Logbook (#553): the switch that measures them, a
/// row for each attempt with a column for each measure it reached, and the stops. The best of each
/// measure is marked; a note says when an attempt was on a slope or logged slowly, rather than
/// hiding it.
struct SessionPerformanceSection: View {
    let entry: LogbookEntry
    /// A driver who reads km/h is shown 0–100 km/h and the marks in metres.
    let metric: Bool
    /// Measures the session, or stops; `false` when its file could not be read.
    let measure: (Bool) async -> Bool

    @State private var reading = false
    @State private var unreadable = false

    private var performance: PerformanceRuns.Result? { entry.performance }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Performance").font(.subheadline.weight(.semibold))
                Spacer()
                if reading { ProgressView().controlSize(.small) }
                Toggle("Performance runs", isOn: switchBinding)
                    .disabled(reading)
                    .help(
                        "Time every standing start and every stop: 0–60, the quarter mile, 60–0. On by itself "
                            + "for a logger's file with no laps and no runs; a camera's recording is timed "
                            + "when you turn this on"
                    )
                    .accessibilityIdentifier("logbook.performance.measure")
            }
            if unreadable {
                Text("Its data file could not be read: it is not where the logbook has it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let performance, entry.measuresPerformanceInForce {
                if performance.isEmpty {
                    Text(
                        "No standing starts or stops found: a launch is timed from standing still, and a stop "
                            + "from \(metric ? "100 km/h" : "60 mph") to standing still."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    if !performance.attempts.isEmpty { attempts(performance) }
                    if !stops(performance).isEmpty { stopTable(performance) }
                }
            }
        }
        .font(.callout)
        .onChange(of: entry.id) {
            unreadable = false
        }
    }

    private var switchBinding: Binding<Bool> {
        Binding(
            get: { entry.measuresPerformanceInForce },
            set: { on in
                reading = true
                unreadable = false
                Task {
                    unreadable = !(await measure(on))
                    reading = false
                }
            })
    }

    // MARK: - Launches

    private func speedColumns(_ performance: PerformanceRuns.Result) -> [PerformanceRuns.SpeedRange] {
        PerformanceWording.speedRanges(metric: metric).filter { range in
            performance.attempts.contains { $0.speedTimes[range] != nil }
        }
    }

    private func markColumns(_ performance: PerformanceRuns.Result) -> [PerformanceRuns.DragDistance] {
        PerformanceRuns.DragDistance.allCases.filter { mark in
            performance.attempts.contains { $0.distanceTimes[mark] != nil }
        }
    }

    @ViewBuilder private func attempts(_ performance: PerformanceRuns.Result) -> some View {
        let ranges = speedColumns(performance)
        let hasNotes = performance.attempts.contains { !$0.notes.isEmpty }
        let marks = markColumns(performance)
        let best = (
            ranges: Dictionary(
                uniqueKeysWithValues: ranges.compactMap { r in performance.best(r).map { (r, $0.attempt) } }),
            marks: Dictionary(
                uniqueKeysWithValues: marks.compactMap { m in performance.best(m).map { (m, $0.attempt) } })
        )
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                GridRow {
                    Text("Start")
                    ForEach(ranges, id: \.self) { Text($0.label) }
                    ForEach(marks, id: \.self) { Text($0.label(metric: metric)) }
                    if hasNotes { Text("Notes") }
                }
                .foregroundStyle(.secondary)
                ForEach(Array(performance.attempts.enumerated()), id: \.offset) { index, attempt in
                    GridRow {
                        Text("Start \(index + 1)")
                        ForEach(ranges, id: \.self) { range in
                            cell(
                                attempt.speedTimes[range].map(PerformanceWording.seconds),
                                best: best.ranges[range] == index,
                                name: range.label)
                        }
                        ForEach(marks, id: \.self) { mark in
                            cell(
                                attempt.distanceTimes[mark].map {
                                    PerformanceWording.mark($0, trap: attempt.trapSpeeds[mark], metric: metric)
                                }, best: best.marks[mark] == index, name: mark.label(metric: metric))
                        }
                        if hasNotes { Text(attempt.notes.joined(separator: "; ")).foregroundStyle(.secondary) }
                    }
                }
            }
            .monospacedDigit()
            .padding(.bottom, 4)
        }
        Text(
            "Speed times run from standing still. Distance times use a \(PerformanceWording.rollout); "
                + "a trap speed is the mean over the last 66 ft."
        )
        .font(.caption).foregroundStyle(.secondary)
    }

    /// A measure's value, in the accent colour when it is the session's best; a dash when the
    /// attempt never reached it.
    private func cell(_ value: String?, best: Bool, name: String) -> some View {
        Text(value ?? "—")
            .foregroundStyle(best ? Color.accentColor : value == nil ? .secondary : .primary)
            .accessibilityLabel(value.map { "\(name) \($0)\(best ? ", best" : "")" } ?? "\(name) not reached")
    }

    // MARK: - Stops

    private func stops(_ performance: PerformanceRuns.Result) -> [PerformanceRuns.Stop] {
        performance.stops.filter { $0.from == PerformanceWording.braking(metric: metric) }
    }

    @ViewBuilder private func stopTable(_ performance: PerformanceRuns.Result) -> some View {
        let braking = PerformanceWording.braking(metric: metric)
        let shown = stops(performance)
        let best = shown.indices.min { shown[$0].metres < shown[$1].metres }
        let hasNotes = shown.contains { !$0.notes.isEmpty }
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
            GridRow {
                Text("Stop")
                Text("\(braking.label) distance")
                Text("Time")
                if hasNotes { Text("Notes") }
            }
            .foregroundStyle(.secondary)
            ForEach(Array(shown.enumerated()), id: \.offset) { index, stop in
                GridRow {
                    Text("Stop \(index + 1)")
                    cell(
                        PerformanceWording.distance(stop.metres, metric: metric), best: index == best,
                        name: "\(braking.label) distance")
                    Text(PerformanceWording.seconds(stop.seconds))
                    if hasNotes { Text(stop.notes.joined(separator: "; ")).foregroundStyle(.secondary) }
                }
            }
        }
        .monospacedDigit()
    }
}
