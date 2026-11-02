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
                Text(opportunity.note.headline).font(.headline)
                ForEach(opportunity.note.evidence, id: \.self) { line in
                    Label(line, systemImage: "circle.fill")
                        .labelStyle(EvidenceLabelStyle())
                        .font(.callout)
                }
                Text(opportunity.note.suggestion).font(.callout).foregroundStyle(.secondary)
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

    var body: some View {
        let format = CoachingNotes.Formatter(units: units)
        Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Turn", value: \.index) { row in Text(row.label) }.width(min: 44, ideal: 56)
            TableColumn("Time Lost", value: \.timeLost) { row in
                Text((row.timeLost >= 0 ? "+" : "−") + format.seconds(abs(row.timeLost)))
                    .foregroundStyle(row.timeLost > 0.03 ? Color.red : row.timeLost < -0.03 ? Color.green : .primary)
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
        .accessibilityIdentifier("coaching.table")
    }
}
