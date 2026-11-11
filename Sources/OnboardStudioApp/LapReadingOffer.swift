import MediaKit
import ProjectModel
import SwiftUI

/// Sessions whose laps were read before a correction (#498), and a button that reads their files
/// again — as Trends offers for corners measured before a correction (#438). The laps are kept
/// in the entry when a session is added and never read again, so a RaceChrono session added
/// before #477 went on showing a first lap that had swallowed the out-lap, or one lap too few.
/// Asked for rather than done unasked: it reads every file, and it can change a best lap.
struct LapReadingOffer: View {
    /// The sessions on show that the correction can change.
    let entries: [LogbookEntry]
    let done: () -> Void
    @State private var reading = false
    /// Sessions whose file was not found the last time, so the offer does not come straight back
    /// for them.
    @State private var unread: Set<UUID> = []

    private var waiting: [LogbookEntry] { entries.filter { !unread.contains($0.id) } }

    var body: some View {
        if !waiting.isEmpty || !unread.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(Self.text(waiting: waiting.count, unread: unread.count))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("logbook.lapReading.text")
                Spacer()
                if !waiting.isEmpty {
                    Button(
                        reading ? "Reading…" : waiting.count == 1 ? "Read It Again" : "Read Them Again", action: read
                    )
                    .disabled(reading)
                    .help("Reads the files again; the car, the conditions and the notes are kept")
                    .accessibilityIdentifier("logbook.lapReading.read")
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    /// "3 sessions here were read before a correction to the first lap."
    static func text(waiting: Int, unread: Int) -> String {
        func sessions(_ count: Int) -> String { "\(count) session\(count == 1 ? "" : "s")" }
        var parts: [String] = []
        if waiting > 0 {
            parts.append(
                "\(sessions(waiting)) here \(waiting == 1 ? "was" : "were") read before a correction to the first lap.")
        }
        if unread > 0 {
            let place =
                unread == 1
                ? "its file is not where the logbook has it" : "their files are not where the logbook has them"
            parts.append("\(sessions(unread)) could not be read again: \(place).")
        }
        return parts.joined(separator: " ")
    }

    private func read() {
        reading = true
        let ids = waiting.map(\.id)
        Task {
            let logbook = AppLogbook.shared
            let missing = await Task.detached(priority: .utility) {
                LogbookReferences.readLapsAgain(of: ids, in: logbook)
            }.value
            unread.formUnion(missing)
            reading = false
            done()
        }
    }
}
