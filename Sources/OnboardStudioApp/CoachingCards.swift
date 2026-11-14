import ProjectModel
import SwiftUI
import TelemetryKit

/// One opportunity: what happened, the evidence, what to try, and the way to the video.
struct OpportunityCard: View {
    let opportunity: Opportunity
    let showMe: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                // In full: cut to a line, what to try was the part that could not be read (#458).
                Text(opportunity.note.headline).font(.headline).fixedSize(horizontal: false, vertical: true)
                ForEach(opportunity.note.evidence, id: \.self) { line in
                    Label(line, systemImage: "circle.fill")
                        .labelStyle(EvidenceLabelStyle())
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(opportunity.note.suggestion).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coaching.suggestion.\(opportunity.rank)")
                Spacer(minLength: 0)
                Button("Show Me", action: showMe)
                    .accessibilityLabel("Show Me Turn \(opportunity.corner.label)")
                    .accessibilityIdentifier("coaching.showMe.\(opportunity.rank)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("coaching.opportunity.\(opportunity.rank)")
    }
}

/// A small bullet, so the evidence reads as a list rather than a row of icons.
struct EvidenceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

/// Every corner, sortable by any column.
struct CornerTable: View {
    let rows: [CornerRow]
    @Binding var selection: Int?
    @Binding var sortOrder: [KeyPathComparator<CornerRow>]
    let units: CoachingUnits
    /// Marks a corner as held up by traffic or a flag, or clears its mark (#571).
    var mark: ((Int, TrafficSpan.Kind?) -> Void)?
    /// Dismisses the telemetry's traffic suggestion for a corner (#572).
    var dismissSuggestion: ((TrafficSuggestion) -> Void)?

    var body: some View {
        let format = CoachingNotes.Formatter(units: units)
        Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Turn", value: \.index) { row in
                HStack(spacing: 4) {
                    Text(row.label)
                    if row.suggestion != nil {
                        Image(systemName: "car.2")
                            .foregroundStyle(.secondary)
                            .help("The telemetry suggests traffic here")
                            .accessibilityLabel("Possibly Traffic")
                            .accessibilityIdentifier("coaching.table.suggested.\(row.index)")
                    }
                }
            }
            .width(min: 52, ideal: 64)
            TableColumn("Time Lost", value: \.timeLost) { row in
                Text((row.timeLost >= 0 ? "+" : "−") + format.seconds(abs(row.timeLost)))
                    .foregroundStyle(timeColor(row))
                    .monospacedDigit()
            }
            .width(min: 72, ideal: 84)
            TableColumn("Phase", value: \.phase) { row in Text(row.phase) }.width(min: 60, ideal: 72)
            TableColumn("Brake", value: \.brakeOrder) { row in Text(row.brake) }.width(min: 80, ideal: 96)
            TableColumn("Min Speed", value: \.minimumSpeedDifference) { row in Text(row.minimumSpeed) }
                .width(min: 80, ideal: 96)
            TableColumn("Where", value: \.minimumPointDifference) { row in Text(row.minimumPoint) }
                .width(min: 72, ideal: 88)
            TableColumn("Exit", value: \.exitSpeedDifference) { row in Text(row.exitSpeed) }.width(min: 72, ideal: 88)
            TableColumn("Throttle", value: \.throttleOrder) { row in Text(row.throttle) }.width(min: 80, ideal: 96)
            TableColumn("Consistent", value: \.consistency) { row in Text(row.consistent) }.width(min: 90, ideal: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int.self) { indices in
            if let mark, let index = indices.first, let row = rows.first(where: { $0.index == index }) {
                Button("Mark Turn \(row.label) as Traffic") { mark(index, .traffic) }
                Button("Mark Turn \(row.label) as a Flag") { mark(index, .flag) }
                if row.traffic?.onLap == true {
                    Divider()
                    Button("Clear Traffic Mark") { mark(index, nil) }
                }
                if let suggestion = row.suggestion, let dismissSuggestion {
                    Divider()
                    Button("Dismiss Traffic Suggestion") { dismissSuggestion(suggestion) }
                }
            }
        }
        .accessibilityIdentifier("coaching.table")
    }

    /// Lost in red, gained in green; a corner held up by traffic in neither, since the time is
    /// not the driver's.
    private func timeColor(_ row: CornerRow) -> Color {
        if row.traffic != nil { return .secondary }
        return row.timeLost > 0.03 ? .red : row.timeLost < -0.03 ? .green : .primary
    }
}
