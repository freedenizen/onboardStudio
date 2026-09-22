import SwiftUI
import TelemetryKit

/// What became of every column of the file, with room for the columns to be columns (#149, #192).
struct ImportReportTable: View {
    let report: ImportReport

    @State private var showEverything = false

    private var rows: [ImportReport.Column] {
        showEverything ? report.columns : report.needingAttention
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Column").frame(width: 200, alignment: .leading)
                Text("From").frame(width: 120, alignment: .leading)
                Text("Became").frame(width: 200, alignment: .leading)
                Text("Notes").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 6)
            Divider()
            if report.columns.isEmpty {
                ContentUnavailableView("Nothing imported yet", systemImage: "doc")
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "Every column read cleanly", systemImage: "checkmark.circle",
                    description: Text("Turn on “Show every column” to see them all.")
                )
                .accessibilityIdentifier("import.clean")
            } else {
                List {
                    ForEach(rows) { column in ImportReportTableRow(column: column) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            HStack {
                Toggle("Show every column", isOn: $showEverything)
                    .accessibilityIdentifier("import.showAll")
                Spacer()
                Text(report.summary).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("import.summary")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

private struct ImportReportTableRow: View {
    let column: ImportReport.Column

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 6) {
                if column.needsAttention {
                    Image(systemName: column.role == nil ? "xmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(column.role == nil ? .red : .orange)
                }
                Text(column.name).lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 200, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("import.\(column.id)")
            Text(column.source ?? "—").foregroundStyle(.secondary).lineLimit(1)
                .frame(width: 120, alignment: .leading)
            Text(became).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(width: 200, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(column.notes.enumerated()), id: \.offset) { _, note in
                    Text(note.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var became: String {
        guard let role = column.role else { return "not imported" }
        let unit = column.unit.symbol
        return unit.isEmpty ? role.identifier : "\(role.identifier) · \(unit)"
    }
}
