import MediaKit
import SwiftUI

/// Along the foot of the Logbook's sessions while files are added with their sheet away (#664):
/// how far the reading has got, and a button that brings the sheet back. Nothing in the window
/// said an import was still running, and sessions arrived in the table for a minute unexplained.
struct ImportActivityBar: View {
    private var runs = ImportRuns.shared

    var body: some View {
        if let run = runs.inBackground.first {
            let activity = run.activity
            let others = runs.inBackground.count - 1
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    ProgressView(value: activity.fraction)
                        .controlSize(.small)
                        .frame(width: 120)
                        .accessibilityLabel("Adding files to the logbook")
                    Text(others > 0 ? "\(activity.line) \(others) more to add after." : activity.line)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("logbook.import.line")
                    Button(activity.showTitle) { run.showSheet() }
                        .controlSize(.small)
                        .help("Show the files being added and what happened to each")
                        .accessibilityIdentifier("logbook.import.show")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)
        }
    }
}
