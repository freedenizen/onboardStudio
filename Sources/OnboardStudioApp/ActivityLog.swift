import AppKit
import MediaKit
import SwiftUI

/// Everything the app has told the user in one project's window, newest last (#112): the status
/// line keeps one message, and a message replaced a moment later — an import finishing while an
/// auto-sync applies — used to be gone before it could be read.
struct ActivityLog {
    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let text: String
        /// An error the user was shown in an alert, rather than a report of something done.
        let isProblem: Bool
    }

    /// Enough for a long session; the oldest go first.
    static let limit = 500

    private(set) var entries: [Entry] = []

    mutating func record(_ text: String, isProblem: Bool = false, at date: Date = Date()) {
        entries.append(Entry(date: date, text: text, isProblem: isProblem))
        if isProblem {
            Diagnostics.activity.error("\(text, privacy: .public)")
        } else {
            Diagnostics.activity.info("\(text, privacy: .public)")
        }
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// The log as plain text, one line per entry, for pasting into a bug report.
    var text: String {
        entries.map { entry in
            let time = entry.date.formatted(date: .omitted, time: .standard)
            return "\(time)\(entry.isProblem ? " [problem]" : "")  \(entry.text)"
        }
        .joined(separator: "\n")
    }
}

/// The status line's history, newest first, selectable and copyable.
struct ActivityLogView: View {
    let log: ActivityLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.text, forType: .string)
                }
                .disabled(log.entries.isEmpty)
                .accessibilityIdentifier("activity.copy")
            }
            .padding(12)
            Divider()
            if log.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing Yet", systemImage: "clock",
                    description: Text(
                        "What the app does for you — files joined, data synced, anything refused — is listed here."))
            } else {
                List(log.entries.reversed()) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        if entry.isProblem {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                .accessibilityLabel("Problem")
                        }
                        Text(entry.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("activity.entry")
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 440, height: 320)
    }
}
