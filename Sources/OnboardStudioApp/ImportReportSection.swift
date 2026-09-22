import SwiftUI
import TelemetryKit

/// What became of every column of this data file (#149).
///
/// The channel list shows what survived and says nothing about what did not, or about what quietly
/// lost its meaning on the way in. This says it: which column kept a contested role, which sensor
/// read the same number all session, which unit the app could not place.
///
/// Collapsed to the columns worth a look, because on a real CAN log that is a handful out of
/// thirty and the rest are simply fine.
struct ImportReportSection: View {
    let report: ImportReport

    @State private var showEverything = false

    private var shown: [ImportReport.Column] {
        showEverything ? report.columns : report.needingAttention
    }

    var body: some View {
        Section {
            if report.columns.isEmpty {
                Text("Nothing imported yet.").foregroundStyle(.secondary)
            } else if report.needingAttention.isEmpty && !showEverything {
                Label("Every column read cleanly.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("import.clean")
            } else {
                ForEach(shown) { column in
                    ImportReportRow(column: column)
                }
            }
            if !report.columns.isEmpty {
                Toggle("Show every column", isOn: $showEverything)
                    .accessibilityIdentifier("import.showAll")
            }
        } header: {
            Text("Import")
        } footer: {
            Text(report.summary).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("import.summary")
        }
    }
}

/// One column: what it is called, what it became, and anything worth saying about it.
private struct ImportReportRow: View {
    let column: ImportReport.Column

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if column.needsAttention {
                    Image(systemName: column.role == nil ? "xmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(column.role == nil ? .red : .orange)
                }
                Text(column.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(became).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("import.\(column.id)")
            ForEach(Array(column.notes.enumerated()), id: \.offset) { _, note in
                Text(note.message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The right-hand summary: the channel it became and the unit it was read in. A column that
    /// became nothing says so rather than showing an empty space.
    private var became: String {
        guard let role = column.role else { return "not imported" }
        let unit = column.unit.symbol
        return unit.isEmpty ? role.identifier : "\(role.identifier) · \(unit)"
    }
}
