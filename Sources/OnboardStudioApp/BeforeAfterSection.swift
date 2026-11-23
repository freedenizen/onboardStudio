import ProjectModel
import SwiftUI

/// Trends narrowed to sessions on one tyre set, setup, surface or weather (#559): a pop-up for each
/// that the circuit's sessions noted two or more of.
struct TrendsFilterBar: View {
    let choices: TrendsFilter.Choices
    @Binding var filter: TrendsFilter

    static func isUseful(_ choices: TrendsFilter.Choices) -> Bool {
        choices.tyres.count >= 2 || choices.setups.count >= 2 || choices.surfaces.count >= 2
            || choices.weathers.count >= 2
    }

    var body: some View {
        // In rows, as text wraps: side by side they are wider than the Logbook's middle column
        // at the size the window first opens, and the page lost its left edge to them (#659).
        FlowLayout {
            if choices.tyres.count >= 2 {
                Picker("Tyres", selection: $filter.tyres) {
                    Text("Every Set").tag(String?.none)
                    ForEach(choices.tyres, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .fixedSize()
                .accessibilityIdentifier("logbook.trends.filter.tyres")
            }
            if choices.setups.count >= 2 {
                Picker("Setup", selection: $filter.setup) {
                    Text("Every Setup").tag(String?.none)
                    ForEach(choices.setups, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .fixedSize()
                .accessibilityIdentifier("logbook.trends.filter.setup")
            }
            if choices.surfaces.count >= 2 {
                Picker("Surface", selection: $filter.surface) {
                    Text("Every Surface").tag(SessionConditions.Track?.none)
                    ForEach(choices.surfaces, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .fixedSize()
                .accessibilityIdentifier("logbook.trends.filter.surface")
            }
            if choices.weathers.count >= 2 {
                Picker("Weather", selection: $filter.weather) {
                    Text("Any Weather").tag(SessionConditions.Weather?.none)
                    ForEach(choices.weathers, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .fixedSize()
                .accessibilityIdentifier("logbook.trends.filter.weather")
            }
            if !filter.isEmpty {
                Button("Show All") { filter = TrendsFilter() }
                    .help("Every session at the circuit, whatever its tyres, setup or conditions")
                    .accessibilityIdentifier("logbook.trends.filter.clear")
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Did a change help (#559): the sessions at a circuit split by one tyre set, setup, surface,
/// weather or setup value, the two sides read across the whole lap, every sector and every corner.
struct BeforeAfterSection: View {
    /// The circuit's sessions, already narrowed by the car and the filters.
    let entries: [LogbookEntry]
    let format: LogbookTrends.CornerFormat
    @State private var split: SetupSplit?
    @State private var before: String?
    @State private var after: String?

    private var units: SetupUnits { .app }
    private var splits: [SetupSplit] { SetupComparison.splits(in: entries) }
    private var values: [(key: String, label: String)] {
        split.map { SetupComparison.values(of: $0, in: entries, units: units) } ?? []
    }
    private var comparison: SetupComparison? {
        guard let split, let before, let after else { return nil }
        return SetupComparison.compare(split, before: before, after: after, in: entries, units: units)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // On the title, not the stack: a stack's identifier would replace its children's.
            Text("Before and after").font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("logbook.trends.beforeAfter")
            if splits.isEmpty {
                Text(
                    "Note the tyres, the setup or the conditions on the sessions here and this compares the "
                        + "sessions driven one way with those driven another, across the lap, every sector and "
                        + "every corner."
                )
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("logbook.trends.beforeAfter.empty")
            } else {
                pickers
                if let comparison { BeforeAfterResult(comparison: comparison, format: format) }
            }
        }
        .onAppear(perform: choose)
        .onChange(of: splits) { choose() }
        .onChange(of: split) { chooseValues() }
    }

    private var pickers: some View {
        // In rows, as the filter bar is (#659).
        FlowLayout {
            Picker("Compare by", selection: $split) {
                ForEach(splits, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            .fixedSize()
            .accessibilityIdentifier("logbook.trends.beforeAfter.split")
            Picker("Before", selection: $before) {
                ForEach(values, id: \.key) { Text($0.label).tag(Optional($0.key)) }
            }
            .fixedSize()
            .accessibilityIdentifier("logbook.trends.beforeAfter.before")
            Picker("After", selection: $after) {
                ForEach(values, id: \.key) { Text($0.label).tag(Optional($0.key)) }
            }
            .fixedSize()
            .accessibilityIdentifier("logbook.trends.beforeAfter.after")
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first split the sessions differ by, unless the one chosen still applies.
    private func choose() {
        if let split, splits.contains(split) { return }
        split = splits.first
        chooseValues()
    }

    /// The last two values driven: the one before the latest, and the latest.
    private func chooseValues() {
        let keys = values.map(\.key)
        if let before, let after, keys.contains(before), keys.contains(after) { return }
        after = keys.last
        before = keys.dropLast().last
    }
}

/// The two sides, as numbers and as sentences.
struct BeforeAfterResult: View {
    let comparison: SetupComparison
    let format: LogbookTrends.CornerFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(comparison.headline).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("logbook.trends.beforeAfter.headline")
            ForEach(comparison.caveats, id: \.self) { caveat in
                Label(caveat, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            summaryGrid
            if let sectors = comparison.sectorSentence() {
                Text(sectors).font(.callout).accessibilityIdentifier("logbook.trends.beforeAfter.sectors")
            }
            if let corners = comparison.cornerSentence() {
                Text(corners).font(.callout).accessibilityIdentifier("logbook.trends.beforeAfter.corners")
            }
            if !comparison.cornerDifferences.isEmpty { cornerGrid }
        }
    }

    private var summaryGrid: some View {
        let a = comparison.before
        let b = comparison.after
        return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text(a.label).fontWeight(.semibold)
                Text(b.label).fontWeight(.semibold)
                Text("Difference").fontWeight(.semibold)
            }
            row("Sessions", String(a.sessions), String(b.sessions), nil)
            row("Average best", time(a.averageBest), time(b.averageBest), comparison.averageBestDifference)
            row("Best", time(a.best), time(b.best), difference(a.best, b.best))
            row("Optimal", time(a.optimal), time(b.optimal), difference(a.optimal, b.optimal))
            row("Lap spread", spread(a.spread), spread(b.spread), difference(a.spread, b.spread))
        }
        .font(.callout.monospacedDigit())
        .accessibilityIdentifier("logbook.trends.beforeAfter.table")
    }

    private var cornerGrid: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("Corner").fontWeight(.semibold).gridColumnAlignment(.leading)
                Text("Minimum speed").fontWeight(.semibold)
                Text("Time").fontWeight(.semibold)
            }
            ForEach(comparison.cornerDifferences, id: \.label) { corner in
                GridRow {
                    Text(corner.label)
                    Text(format.minimumSpeedChange(corner.minimumSpeed))
                    Text(String(format: "%+.2f s", corner.time))
                }
            }
        }
        .font(.callout.monospacedDigit())
    }

    private func row(_ title: String, _ a: String, _ b: String, _ change: Double?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(a)
            Text(b)
            Text(change.map { String(format: "%+.2f s", $0) } ?? "—")
        }
    }

    private func time(_ seconds: Double?) -> String { seconds.map(LogbookTrends.lapTime) ?? "—" }
    private func spread(_ seconds: Double?) -> String { seconds.map { String(format: "±%.2f s", $0) } ?? "—" }
    private func difference(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return b - a
    }
}
