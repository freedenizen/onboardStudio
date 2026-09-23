import SwiftUI
import TelemetryKit

/// What became of every column of the file, with room for the columns to be columns (#149, #192).
///
/// A system table (#200): column headers that resize, rows chosen with ↑ and ↓, VoiceOver reading
/// each cell with its column's name, and ⌘C copying the chosen rows as text — for pasting into a
/// bug report or a message to whoever wired the logger. Nothing in it is editable, so the table
/// view keeping Tab to itself costs nothing here.
struct ImportReportTable: View {
    let report: ImportReport
    /// What was typed in the window's filter field.
    let filter: String
    @Binding var showEverything: Bool

    @State private var selection = Set<ImportReport.Column.ID>()
    @ScaledMetric(relativeTo: .body) private var rowInset: CGFloat = 4

    private var isFiltering: Bool { !filter.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The columns with something to say, or all of them when asked — and while filtering, all of
    /// them that match, because typing a column's name is asking for it.
    private var rows: [ImportReport.Column] {
        if isFiltering { return report.columns.filter { $0.matches(filter: filter) } }
        return showEverything ? report.columns : report.needingAttention
    }

    var body: some View {
        Group {
            if report.columns.isEmpty {
                ContentUnavailableView(
                    "Nothing imported yet", systemImage: "doc",
                    description: Text("The file is still loading, or it had no columns this app could read."))
            } else if rows.isEmpty, isFiltering {
                ContentUnavailableView.search(text: filter)
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "Every column read cleanly", systemImage: "checkmark.circle",
                    description: Text("Turn on “Show every column” to see them all.")
                )
                .accessibilityIdentifier("import.clean")
            } else {
                table
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                footer
            }
            .background(.bar)
        }
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Column") { column in
                HStack {
                    if column.needsAttention {
                        Image(systemName: column.role == nil ? "xmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(column.role == nil ? .red : .orange)
                            .accessibilityLabel(column.role == nil ? "Not imported" : "Worth a look")
                    }
                    Text(column.name).lineLimit(1).truncationMode(.middle)
                }
                .help(column.name)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("import.\(column.id)")
            }
            .width(min: 140, ideal: 200)
            TableColumn("From") { column in
                Text(column.source ?? "—").foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityLabel(column.source ?? "No group")
            }
            .width(min: 80, ideal: 120)
            TableColumn("Became") { column in
                Text(column.becameDescription).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(column.becameDescription)
            }
            .width(min: 120, ideal: 200)
            TableColumn("Notes") { column in
                Text(notes(of: column)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onCopyCommand { [copyText(of: selectedRows)].compactMap { $0 }.map { NSItemProvider(object: $0 as NSString) } }
        .accessibilityIdentifier("import.table")
    }

    private var footer: some View {
        HStack {
            Toggle("Show every column", isOn: $showEverything)
                .disabled(isFiltering)
                .help(
                    isFiltering
                        ? "A filter searches every column already"
                        : "Also list the columns that were read without anything worth saying"
                )
                .accessibilityIdentifier("import.showAll")
            Spacer()
            Text(report.summary).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("import.summary")
        }
        .padding(.horizontal)
        .padding(.vertical, rowInset * 2)
    }

    private func notes(of column: ImportReport.Column) -> String {
        column.notes.map(\.message).joined(separator: "\n")
    }

    private var selectedRows: [ImportReport.Column] { rows.filter { selection.contains($0.id) } }

    /// The chosen rows as tab-separated text, a header first, which pastes as a table into a
    /// spreadsheet and reads plainly anywhere else.
    private func copyText(of columns: [ImportReport.Column]) -> String? {
        guard !columns.isEmpty else { return nil }
        let lines = columns.map { column in
            [column.name, column.source ?? "", column.becameDescription, notes(of: column).replacing("\n", with: " ")]
                .joined(separator: "\t")
        }
        return (["Column\tFrom\tBecame\tNotes"] + lines).joined(separator: "\n")
    }
}
