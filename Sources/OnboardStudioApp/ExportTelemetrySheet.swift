import Importers
import ProjectModel
import SwiftUI
import TelemetryKit
import UniformTypeIdentifiers

/// Export Telemetry… (#563): a session, or one lap of it, written in an open format for another app,
/// a friend or an instructor — every channel as CSV, the path as GPX or KML, or Racelogic's VBO.
struct ExportTelemetrySheet: View {
    let entry: LogbookEntry
    /// Says what was written, in the window's status line.
    var exported: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exportTelemetry.format") private var formatChoice = TelemetryExport.Format.csv.rawValue
    @State private var lap: Int?
    @State private var problem: String?
    @State private var isWriting = false

    private var format: TelemetryExport.Format { TelemetryExport.Format(rawValue: formatChoice) ?? .csv }
    private var laps: [LogbookEntry.LapRecord] { entry.laps.filter(\.isComplete) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Telemetry").font(.title2)
            Text(
                "\(entry.title), as the app reads it — with its trim, its laps and its start/finish line — for "
                    + "another app, a friend or an instructor."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Format", selection: $formatChoice) {
                    ForEach(TelemetryExport.Format.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("exportTelemetry.format")
                Picker("Laps", selection: $lap) {
                    Text("The whole session").tag(Int?.none)
                    ForEach(laps, id: \.number) { lap in
                        Text(lapTitle(lap)).tag(Optional(lap.number))
                    }
                }
                .accessibilityIdentifier("exportTelemetry.lap")
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("exportTelemetry.problem")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isWriting ? "Exporting…" : "Export…", action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWriting)
                    .accessibilityIdentifier("exportTelemetry.export")
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { lap = entry.bestLapNumber }
    }

    private func lapTitle(_ lap: LogbookEntry.LapRecord) -> String {
        let time = lap.seconds.map { " · \(TimeParsing.lapTimeString($0, decimals: 2))" } ?? ""
        return "Lap \(lap.number)\(time)" + (lap.number == entry.bestLapNumber ? " (best)" : "")
    }

    private func export() {
        problem = nil
        isWriting = true
        let format = format
        let scope: TelemetryExport.Scope = lap.map { .lap($0) } ?? .session
        let name = [entry.title, lap.map { "Lap \($0)" }].compactMap { $0 }.joined(separator: " ")
        Task { @MainActor in
            defer { isWriting = false }
            guard let session = await LogbookModel.shared.session(for: entry) else {
                problem = "The session's file could not be read. It may have moved: Show in Finder says where it was."
                return
            }
            do {
                let data = try TelemetryExport.export(session, as: format, scope: scope, name: name)
                let type = UTType(filenameExtension: format.fileExtension) ?? .data
                guard
                    let url = OpenPanels.chooseDocumentDestination(
                        title: "Export Telemetry", suggestedName: name, type: type,
                        fileExtension: format.fileExtension)
                else { return }
                try data.write(to: url)
                exported("Exported \(url.lastPathComponent).")
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
