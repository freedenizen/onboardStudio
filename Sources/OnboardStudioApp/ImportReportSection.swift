import SwiftUI
import TelemetryKit

/// What became of every column of this data file (#149).
///
/// The channel list shows what survived and says nothing about what did not, or about what quietly
/// lost its meaning on the way in. This says it: which column kept a contested role, which sensor
/// read the same number all session, which unit the app could not place.
///
/// Says whether anything needs looking at and opens the window that shows it: the report is a
/// list of every column of the file, which an inspector column cannot hold (#192).
struct ImportReportSection: View {
    let report: ImportReport

    var body: some View {
        Section {
            if report.columns.isEmpty {
                Text("Nothing imported yet.").foregroundStyle(.secondary)
            } else if report.needingAttention.isEmpty {
                Label("Every column read cleanly.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("import.clean")
            } else {
                Text(report.summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("import.inspectorSummary")
            }
            OpenAttributeWindowButton("Show Import Report…", identifier: "import.open")
        } header: {
            Text("Import")
        }
    }
}
